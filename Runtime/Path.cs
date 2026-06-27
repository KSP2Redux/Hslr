using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Unity.Collections;
using Unity.Profiling;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Serialization;
using Object = System.Object;

namespace Hslr
{
    [Serializable]
    public struct Path : IDisposable
    {
        public Matrix4x4 objectTrs;
        public Material material;

        [Tooltip("If an extra segment should be generated to connect the last node drawn back to the first node.")]
        public bool loopPath;

        [Tooltip("Limit the number of nodes drawn to less than the entire buffer.  This allows changing the number of segments drawn without resizing the buffer.")]
        public int limitCount;

        [Tooltip("Use an index buffer to reduce vertex shader overhead.  Increases ovreahead when changing the path list length.")]
        public bool useIndexBuffer;

        ComputeBuffer buffer;
        GraphicsBuffer indexBuffer;

        public int nodeCount;

        private List<uint> indexBufferInput;

        private const int vertsPerSegment = 6;

        private static readonly int loopPathId = Shader.PropertyToID("_LoopPath");
        private static readonly int nodeCountId = Shader.PropertyToID("_NodeCount");
        private static readonly int thicknessId = Shader.PropertyToID("_Thickness");
        private static readonly int colorId = Shader.PropertyToID("_Color");
        private static readonly int pathDataBufferId = Shader.PropertyToID("PathDataBuffer");
        private static readonly int dashPeriodId = Shader.PropertyToID("_DashSize");
        private static readonly int dashRatioId = Shader.PropertyToID("_DashRatio");


        private static readonly ProfilerMarker renderToMarker = new("Path.RenderTo()");
        private static readonly ProfilerMarker generateIndexBufferMarker = new("Path.GenerateIndexBuffer()");

        public Color Color { set => material.SetColor(colorId, value); }
        public float Thickness { set => material.SetFloat(thicknessId, value); }
        
        public float DashPeriod
        {
            set => material.SetFloat(dashPeriodId, value);
        }

        public float DashRatio
        {
            set => material.SetFloat(dashRatioId, value);
        }

        public NativeArray<PathNode> BeginWrite(int count)
        {
            EnsurePathBufferCapacity(count);
            nodeCount = count;
            return buffer.BeginWrite<PathNode>(0, count);
        }

        public void RenderTo(CommandBuffer cb)
        {
            if (buffer == null || nodeCount < 2) return;

            using var marker = renderToMarker.Auto();

            int nodesToDraw = limitCount > 0 ? Math.Min(limitCount, nodeCount) : nodeCount;
            int segmentsToDraw = loopPath ? nodesToDraw : nodesToDraw - 1;

            material.SetInteger(loopPathId, loopPath ? 1 : 0);
            material.SetInteger(nodeCountId, nodesToDraw);
            material.SetBuffer(pathDataBufferId, buffer);

            if (useIndexBuffer)
            {
                MaybeSetupIndexBuffer(cb);
                cb.DrawProcedural(indexBuffer, objectTrs, material, 0, MeshTopology.Triangles, segmentsToDraw * vertsPerSegment);
            }
            else
            {
                cb.DrawProcedural(objectTrs, material, 0, MeshTopology.Triangles, segmentsToDraw * vertsPerSegment);
            }
        }

        public void EndWrite(int count) 
        {
            buffer.EndWrite<PathNode>(count);
        }

        private void EnsurePathBufferCapacity(int count)
        {
            if (buffer is not null && buffer.count >= count) return;
            buffer?.Dispose();
            buffer = new(count, Marshal.SizeOf<PathNode>(), ComputeBufferType.Structured, ComputeBufferMode.SubUpdates);
        }

        private void MaybeSetupIndexBuffer(CommandBuffer cb)
        {
            using var marker = generateIndexBufferMarker.Auto();

            bool refillBuffer = false;
            int requiredSize = nodeCount * vertsPerSegment;
            if (indexBufferInput is null || indexBufferInput.Count < requiredSize)
            {
                indexBufferInput ??= new(requiredSize);
                refillBuffer = true;
            }

            if (indexBuffer is null || indexBuffer.count < requiredSize)
            {
                indexBuffer?.Dispose();
                indexBuffer = new(GraphicsBuffer.Target.Index, requiredSize, sizeof(int));
            }

            if (!refillBuffer)
            {
                return;
            }

            indexBufferInput.Clear();
            for (uint i = 0; i < requiredSize; i++)
            {
                uint segmentNum = i / vertsPerSegment;
                uint segmentStart = segmentNum * vertsPerSegment;
                // Verts shared between triangles in the same quad are the same vert.
                // Not merging quad endpoints here due to having to sometimes flip the verts depending on the joint angle,
                // which isn't known until the vertex shader runs.
                switch (i % vertsPerSegment)
                {
                    case 0:
                    case 3:
                        indexBufferInput.Add(segmentStart);
                        continue;
                    case 1:
                        indexBufferInput.Add(segmentStart + 1);
                        continue;
                    case 2:
                    case 4:
                        indexBufferInput.Add(segmentStart + 2);
                        continue;
                    case 5:
                        indexBufferInput.Add(segmentStart + 5);
                        continue;
                }
            }
            cb.SetBufferData(indexBuffer, indexBufferInput);
        }

        public void Dispose()
        {
            buffer?.Dispose();
            indexBuffer?.Dispose();
            UnityEngine.Object.Destroy(material);
        }
    }
}
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace Hslr
{
    /// <summary>
    /// Draws a <see cref="Hslr.Path" /> on the main camera, after the skybox, positioned by this object's transform.
    /// </summary>
    /// <remarks>
    /// The draw is a URP render pass that the component enqueues on the main camera's renderer when that camera
    /// begins rendering, so no renderer feature is needed.
    /// </remarks>
    public class HslrRenderer : MonoBehaviour
    {
        /// <summary>
        /// The path to draw.
        /// </summary>
        public Path path;

        private PathPass _pass;

        private void Start()
        {
            _pass = new PathPass(this);
            RenderPipelineManager.beginCameraRendering += OnBeginCameraRendering;
        }

        private void OnBeginCameraRendering(ScriptableRenderContext context, Camera cam)
        {
            if (cam != Camera.main)
                return;

            path.objectTrs = transform.localToWorldMatrix;
            cam.GetUniversalAdditionalCameraData().scriptableRenderer.EnqueuePass(_pass);
        }

        private void OnDestroy()
        {
            RenderPipelineManager.beginCameraRendering -= OnBeginCameraRendering;
            path.Dispose();
        }

        private sealed class PathPass : ScriptableRenderPass
        {
            private readonly HslrRenderer _owner;

            public PathPass(HslrRenderer owner)
            {
                _owner = owner;
                renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
                // The path draws into the camera color with depth testing, which the backbuffer does not allow.
                requiresIntermediateTexture = true;
            }

            public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
            {
                var resources = frameData.Get<UniversalResourceData>();
                using IUnsafeRenderGraphBuilder builder = renderGraph.AddUnsafePass("HslrRenderer", out PassData data);
                data.Owner = _owner;
                data.Color = resources.activeColorTexture;
                data.Depth = resources.activeDepthTexture;
                builder.UseTexture(data.Color, AccessFlags.ReadWrite);
                builder.UseTexture(data.Depth, AccessFlags.ReadWrite);
                builder.AllowPassCulling(false);
                builder.SetRenderFunc(static (PassData passData, UnsafeGraphContext context) =>
                {
                    CommandBuffer cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                    cmd.SetRenderTarget((RTHandle)passData.Color, (RTHandle)passData.Depth);
                    passData.Owner.path.RenderTo(cmd);
                });
            }

            private class PassData
            {
                public HslrRenderer Owner;
                public TextureHandle Color;
                public TextureHandle Depth;
            }
        }
    }
}
#ifndef HSLRINCLUDE_INCLUDED
#define HSLRINCLUDE_INCLUDED

struct NodeData
{
    float3 position;
    uint color;
};

struct NodeContext
{
    NodeData thisNode;
    NodeData nextNode;
    NodeData prevNode;
};

StructuredBuffer<NodeData> PathDataBuffer;
int _NodeCount;
int _LoopPath;

bool IsSegmentEnd(uint vertexID)
{
    switch (vertexID % 6)
    {
        case 2:
        case 4:
        case 5:
            return true;
    }
    return false;
}

float GetVertThicknessSign(uint vertexID)
{
    switch (vertexID % 6)
    {
        case 0:
        case 3:
        case 5:
            return -1;
    }
    return 1;
}

void GetVertNodeIdsWrapped(uint vertexID, uint nodeCount, out uint previous, out uint thisNode, out uint next)
{
    thisNode = vertexID / 6;

    // these verts are on the next node.
    if (IsSegmentEnd(vertexID))
    {
        thisNode += 1;
    }
    
    // wrap end to beginning
    thisNode %= nodeCount;

    next = (thisNode + 1) % nodeCount;
    
    if (thisNode == 0)
    {
        // wrap beginning to end
        previous = nodeCount - 1;
    }
    else
    {
        previous = thisNode - 1;
    }
}

// gets the previous/current/next data for the node the current vertex belongs to.
// note: a given triangle/quad will have verts on different nodes.
NodeContext ReadFromBuffer(uint vertexID, uint nodeCount, out uint thisNodeIdx)
{
    NodeContext context;
    
    uint previous;
    uint next;
    GetVertNodeIdsWrapped(vertexID, nodeCount, previous, thisNodeIdx, next);
    
    context.prevNode = PathDataBuffer[previous];
    context.thisNode = PathDataBuffer[thisNodeIdx];
    context.nextNode = PathDataBuffer[next];
    return context;
}

float4 UnpackColor(uint color)
{
    float4 ret;
    ret.r = float((color >> 24u) & 0xFFu) / 255;
    ret.g = float((color >> 16u) & 0xFFu) / 255;
    ret.b = float((color >> 8u) & 0xFFu) / 255;
    ret.a = float((color) & 0xFFu) / 255;
    return ret;
}
#endif

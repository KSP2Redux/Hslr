Shader "Hslr/LegacyLine"
{
    Properties
    {
        [MainTexture] _MainTex ("Overlay Texture", 2D) = "white" {}
        [HDR] _Color ("Tint", Color) = (1, 1, 1, 1)
        // [Toggle(_USE_PQS_BUFFER)] _NoComputeBuffer ("Use PathDataBuffer for line data. ", float) = 0.9
        _NodeCount ("Node Count", Integer) = 0
        _Thickness ("Thickness", float) = 0.1
        [Enum(Noots,0,Pixels,1)] _ThicknessSpace ("Thickness Space", Integer) = 0
        _MiterThreshold("Miter Threshold", Range(-1,1)) = 0.8
        _LoopPath ("Loop Path", Integer) = 1
        _Gamma ("Gamma", float) = 1.0
        _DashSize ("Dash Period", float) = 0
        _DashSpacing ("Dash Spacing", float) = 0
    }

    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "HslrBuffer.hlsl"

            struct appdata
            {
                uint vertexID : SV_VertexID;
                // float4 vertex : POSITION;
                // float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 color : COLOR0;
                float dist : TEXCOORD1;
                float total_dist  : TEXCOORD2;
            };

            sampler2D _MainTex;
            float4 _Color;
            float _Gamma;
            float _Thickness;
            float _MiterThreshold;
            float _DashSize;
            float _DashSpacing;
            int _ThicknessSpace;

            float2 WCorrect(float4 positionCs)
            {
                return float2(positionCs.x * positionCs.w, positionCs.y * positionCs.w);
            }

            v2f vert (appdata v)
            {
                v2f o;
                uint thisNodeIdx;
                NodeContext context = ReadFromBuffer(v.vertexID, (uint)_NodeCount, thisNodeIdx);

                float thicknessSign = GetVertThicknessSign(v.vertexID);

                float4 prev = UnityObjectToClipPos(context.prevNode.position);
                float4 current = UnityObjectToClipPos(context.thisNode.position);
                float4 next = UnityObjectToClipPos(context.nextNode.position);

                float2 current_screen = current.xy / current.w * _ScreenParams.xy;
                float2 prev_screen = prev.xy / prev.w * _ScreenParams.xy;
                float2 next_screen = next.xy / next.w * _ScreenParams.xy;
                
                float len = _ThicknessSpace == 0
                                  // "noots" unit from Shapes
                                ? _Thickness * (min(_ScreenParams.x, _ScreenParams.y) / 100)
                                : _Thickness;
                float2 dir = float2(0, 0);

                float flip = 1;
                if (_LoopPath < 1 && thisNodeIdx == 0) {
                    // first node in non-looping path goes toward the second node.
                    dir = normalize(next_screen - current_screen);
                }
                else if (_LoopPath < 1 && thisNodeIdx == _NodeCount - 1) {
                    // last node in non-looping path goes toward second to last node.
                    dir = normalize(current_screen - prev_screen);
                }
                else {
                    // an intermediate point in non-looping path, or all points in looping path.
                    float2 dirA = normalize(current_screen - prev_screen);
                    float2 dirB = normalize(next_screen - current_screen);

                    flip = sign(.1 + sign(dot(dirA, dirB) + _MiterThreshold));

                    dirB *= flip;

                    float2 tangent = (dirA + dirB) / 2; //Divide by two normalizes since len is 2.
                    float2 perp_dirA = float2(-dirA.y, dirA.x);
                    float2 perp_tangent = float2(-tangent.y, tangent.x);

                    dir = tangent;
                    len /= dot(perp_tangent, perp_dirA);
                }

                float2 normal = float2(dir.y, -dir.x);

                bool isSegmentEnd = IsSegmentEnd(v.vertexID);

                if(!isSegmentEnd && (flip < 0))
                {
                    len *= -1;
                }

                // One might think that we should "extrude" only half of the length,
                // since the other point will also be moved away from this point by the same distance.
                // However, we are actually only moving half of len pixels since the space we are working in
                // is twice as large as the screen: (-width, +width) rather than (0, width) and same for the height.
                // Essentially there are two factor of two which cancel each other out.
                normal *= len;
                normal *= _ScreenParams.zw - 1; // Equivalent to `normal /= _ScreenParams.xy` but with less division.

                float2 offset = normal * thicknessSign;

                o.vertex = current + float4(offset * current.w, 0, 0);

                o.uv = float2((thicknessSign + 1) / 2, isSegmentEnd ? 0 : 1);
                o.color = UnpackColor(context.thisNode.color);
                // o.dist = context.thisNode.accumulatedArcLength;

                // For dashed nodes
                if (_DashSize > 0 && _DashSpacing > 0)
                {
                    // TODO: Extract this into a helper
                    int raw_this = v.vertexID / 6 + (IsSegmentEnd(v.vertexID) ? 1 : 0);
                    // We need to prefix sum the accumulated arc length, TODO: Look into using a compute kernel here?
                    float4 start = UnityObjectToClipPos(PathDataBuffer[0].position);
                    float2 p_screen = start.xy / start.w * _ScreenParams.xy;
                    float accum = 0;
                    float dist = 0;
                    for (int i =  1; i < _NodeCount; i++)
                    {
                        float4 node = UnityObjectToClipPos(PathDataBuffer[i % _NodeCount].position);
                        float2 node_screen = node.xy / node.w * _ScreenParams.xy;
                        accum += distance(p_screen,node_screen);
                        p_screen = node_screen;
                        if (i == raw_this)
                        {
                            dist = accum;
                        }
                    }
                    o.dist = dist;
                    o.total_dist = accum;
                }
                else
                {
                    o.dist = 0;
                    o.total_dist = 0;
                }
                
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float4 color = _Color  * i.color;

                color *= tex2D(_MainTex, i.uv);

                // gamma correction meant for situations like using sRGB input colors on a linear render target.
                color.xyz = pow(color.xyz, float3(_Gamma, _Gamma, _Gamma));
                
                if (_DashSize > 0 && _DashSpacing > 0)
                {
                    float raw_period = _ThicknessSpace == 0
                                        // "noots" unit from shapes
                                        ? (_DashSize + _DashSpacing) * min(_ScreenParams.x,_ScreenParams.y)/100
                                        : (_DashSize + _DashSpacing);
                    float space_per_period = _DashSpacing / (_DashSize + _DashSpacing);
                    float dash_per_period = 1 - space_per_period;
                    float period_count = i.total_dist / raw_period;
                    period_count = max(1, floor(period_count + space_per_period)) - space_per_period;
                    float t = i.dist / i.total_dist;
                    float coord = t * period_count - dash_per_period * 0.5;
                    float sdf = abs(frac(coord)*2 - 1);
                    sdf = (sdf - space_per_period) / (1 - space_per_period);
                    float mask = saturate(sdf / fwidth(sdf) + 0.5);
                    color.a *= mask;
                }
                
                return color;
            }
            ENDHLSL
        }
    }
}

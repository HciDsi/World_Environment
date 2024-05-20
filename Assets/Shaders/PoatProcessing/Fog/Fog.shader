Shader "PostProcessing/Fog"
{
    Properties
    {
        _MainTex ("Main Tex", 2D) = "white"
    }
    SubShader
    {
        Cull Off 
        ZWrite Off 
        ZTest Always

        Pass
        {
            HLSLPROGRAM

            #pragma shader_feature_local_fragment _UseNormal

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            CBUFFER_START(UnityPerMateials)
            float4 _MainTex_ST;

            half _FogDensity;
            half4 _FogColor;

            half4x4 _InvProj;
            half4x4 _InvView;

            half3 _BoundMax;
            half3 _BoundMin;
            CBUFFER_END

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            struct VertexIn
            {
                float4 pos      : POSITION;
                float2 uv       : TEXCOORD;
            };

            struct VertexOut
            {
                float4 pos          : SV_POSITION;
                float2 uv           : TEXCOORD0;
            };

            half3 GetWorldPos(half depth, half2 uv)
            {
                half4 view = mul(_InvProj, float4(uv * 2.0 - 1.0, depth, 1.0));
                view.xyz /= view.w;
                half4 world = mul(_InvView,half4(view.xyz, 1.0));
                return world.xyz;
            }

            half2 RayBoxDst(half3 boundMin, half3 boundMax, half3 pos, half3 rayInvDir)
            {
                half3 t1 = (boundMax - pos) * rayInvDir;
                half3 t2 = (boundMin - pos) * rayInvDir;
                half3 tMax = max(t1, t2);
                half3 tMin = min(t1, t2);

                half dstA = max(tMin.x, max(tMin.y, tMin.z));
                half dstB = min(tMax.x, min(tMax.y, tMax.z));

                half dstToBox = max(0.0, dstA);
                half dstInsideBox = max(0.0, dstB - dstToBox);

                return half2(dstToBox, dstInsideBox);
            }

            half4 RayMarching(half step, half dstLimit, half3 pos, half3 dir)
            {
                half4 cloud = 0;
                half density = 0;
                half rayL = 0;

                for(int i = 0; i < 32; i++)
                {
                    if(rayL < dstLimit)
                    {
                        density += 0.01;
                        if(density > 1)
                            break;
                    }
                    rayL += step;
                }

                return half4(1, 1, 1, density);
            }

            VertexOut vert(VertexIn v)
            {
                VertexPositionInputs pos = GetVertexPositionInputs(v.pos.xyz);
                
                VertexOut o;
                o.pos = pos.positionCS;
                
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);

                return o;
            }

            half4 frag(VertexOut i) : SV_TARGET
            {
                half4 c = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                
                c = lerp(c, 0, _FogDensity);

                half depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv);
                half3 posW = GetWorldPos(depth, i.uv);
                half3 posV = _WorldSpaceCameraPos;
                half3 V = normalize(posW - posV);

                half depthEyeLinear = length(posW - posV);
                half2 dst = RayBoxDst(_BoundMin, _BoundMax, posV, 1 / V);
                half dstToBox = dst.x;
                half dstInsideBox = dst.y;
                half dstLimit = min(dstInsideBox, depthEyeLinear - dstToBox);
                half4 fog = RayMarching(_FogDensity * 2, dstLimit, posW, V);
                c = half4(V, 1);

                return fog.a;
            }

            ENDHLSL
        }
    }
}

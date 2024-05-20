Shader "PostProcessing/Cloud"
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
    
            half _Density;
            
            half _LightAbsorptionTowardSun;
            half _DarknessThreshold;
            half4 _CloudColor1;
            half _ColorOffset1;
            half4 _CloudColor2;
            half _ColorOffset2;
    
            half4x4 _InvProj;
            half4x4 _InvView;
    
            half3 _BoundMax;
            half3 _BoundMin;
    
            half _3DNoiseTilling;
            half _3DNoiseOffset;
    
            half4 _PhasePamas;
            CBUFFER_END
    
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
    
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);
    
            TEXTURE3D(_3DNoise);
            SAMPLER(sampler_3DNoise);

            TEXTURE2D(_WeatherTex);
            SAMPLER(sampler_WeatherTex);
    
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
                half3 t1 = (boundMin - pos) * rayInvDir;
                half3 t2 = (boundMax - pos) * rayInvDir;
                half3 tMin = min(t1, t2);
                half3 tMax = max(t1, t2);

                half dstA = max(tMin.x, max(tMin.y, tMin.z));
                half dstB = min(tMax.x, min(tMax.y, tMax.z));

                half dstToBox = max(0.0, dstA);
                half dstInsideBox = max(0.0, dstB - dstToBox);

                return half2(dstToBox, dstInsideBox);
            }
    
            float Remap(half original_value, half original_min, half original_max, half new_min, half new_max)
            {
                return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
            }

            half SamplerDensity(half3 pos)
            {
                half3 size = _BoundMax - _BoundMin;
                half3 boundCentre = (_BoundMax + _BoundMin) * 0.5;
                half2 uv = (size.xz * 0.5 + (pos.xz - boundCentre.xz)) / max(size.x, size.z);

                half3 weather = SAMPLE_TEXTURE2D(_WeatherTex, sampler_WeatherTex, uv);
                half heightTemp = (pos.y - _BoundMin.y) / size.y;
                half height = saturate(Remap(heightTemp, 0.0, weather.r, 1.0, 0.0));

                half3 uv3 = pos / (_3DNoiseTilling * size) * 10 + _3DNoiseOffset;
                half4 density = SAMPLE_TEXTURE3D_LOD(_3DNoise, sampler_3DNoise, uv3, 0);

                return density ;
            }
    
            half3 LightMarching(half3 pos)
            {
               Light l = GetMainLight();
               half3 dir = l.direction;
               half dstInsideBox = RayBoxDst(_BoundMin, _BoundMax, pos, 1 / dir).y;
               
               half rayStep = dstInsideBox / 8;
               half d = 0;
               for(int i = 0; i < 8; i++)
               {
                    d += max(0.0, SamplerDensity(pos + i * rayStep * dir));
               }
               half temp = exp(-d * rayStep * _LightAbsorptionTowardSun);

               half3 c = lerp(_CloudColor1, l.color, saturate(temp * _ColorOffset1));
               c = lerp(_CloudColor2, c, saturate(pow(temp * _ColorOffset2, 3)));

               return _DarknessThreshold + (1 - _DarknessThreshold) * temp * c;
            }
    
            half hg(half g, half a)
            {
                half g2 = g * g;
                return (1 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * a, 1.5));
            }
            half Phase(half a)
            {
                half blend = 0.5;
                half hgblend = (1 - blend) * hg(_PhasePamas.x, a) + blend * hg(-_PhasePamas.y, a);
                return _PhasePamas.z + hgblend * _PhasePamas.w;
            }
    
            half4 RayMarching(half rayStep, half dstLimit, half3 pos, half3 dir)
            {
                half density = 1;
                half rayL = 0;
                half3 lightD = 0;

                half VdotL = saturate(dot(dir, GetMainLight().direction));
                half phaseVal = Phase(VdotL);

                for(int i = 0; i < 32; i++)
                {
                    if(rayL < dstLimit)
                    {
                        half3 posW = pos + rayL * dir;
                        half d = SamplerDensity(posW);

                        if(d > 0)
                        {
                            lightD += d * rayStep * density * LightMarching(posW) * phaseVal;
                            density *= exp(-d * rayStep);
                            if(density < 0.01)
                                break;
                        }
                    }

                    rayL += rayStep;
                }

                return half4(lightD, density);
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
    
                half depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv);
                half3 posW = GetWorldPos(depth, i.uv);
                half3 posV = _WorldSpaceCameraPos;
                half3 V = normalize(posW - posV);
    
                half rayEyeLinear = length(posW - posV);
                half2 dst = RayBoxDst(_BoundMin, _BoundMax, posV, 1 / V);
                half dstToBox = dst.x;
                half dstInsideBox = dst.y;
                half dstLimit = min(dstInsideBox, rayEyeLinear - dstToBox);
                half4 cloud = RayMarching(_Density * 2, dstLimit, posV + dstToBox * V, V);

                c = half4(c * cloud.a + cloud.rgb, 1);
    
                return c;
            }
    
            ENDHLSL
        }
    }
}
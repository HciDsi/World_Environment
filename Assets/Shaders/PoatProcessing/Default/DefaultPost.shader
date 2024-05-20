Shader "PostProcessing/Default"
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

                return 1 - c;
            }

            ENDHLSL
        }
    }
}

Shader "Unlit/Sample_Cubemap"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _CubeMap("Cube Map", Cube) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalRenderPipeline" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST;
        CBUFFER_END
        ENDHLSL

        Pass {
            Tags { "LightMode" = "UniversalForward" }

            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct a2v
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
                float3 normal       : NORMAL;
            };

            struct v2f
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                float3 normalWS     : TEXCOORD1;
                float3 viewDirWS    : TEXCOORD2;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURECUBE(_CubeMap);
            SAMPLER(sampler_CubeMap);

            v2f vert(a2v v)
            {
                v2f o;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal);
                float3 viewDirWS = GetCameraPositionWS() - vertexInput.positionWS;
                o.viewDirWS = viewDirWS;
                o.normalWS = normalInput.normalWS;
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.positionCS = vertexInput.positionCS;
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);

                float3 normalWS = normalize(i.normalWS);
                float3 viewDirWS = normalize(i.viewDirWS);
                float3 reflectDirWS = reflect(-viewDirWS, normalWS);
                half4 cubeColor = SAMPLE_TEXTURECUBE(_CubeMap, sampler_CubeMap, reflectDirWS);

                return cubeColor;
            }
            ENDHLSL
        }
    }
}
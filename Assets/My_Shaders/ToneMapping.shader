Shader "ToneMapping"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            static const float3x3 ACESInputMat = 
            {
                {0.59719, 0.35458, 0.04823},
                {0.07600, 0.90834, 0.01566},
                {0.02840, 0.13383, 0.83777}
            };

            static const float3x3 ACESOutputMat = 
            {
                {1.60475, -0.53108, -0.07367},
                {-0.10208, 1.10813, -0.00605},
                {-0.00327, -0.07276, 1.07602}
            };

            float3 RRTAndODTFit(float3 v)
            {
                float3 a = v * (v + 0.0245786f) - 0.000090537f;
                float3 b = v * (0.983729f * v + 0.4329510f) + 0.238081f;
                return a / b;
            }

            float3 ACESFitted(float3 color)
            {
                color = mul(ACESInputMat, color);

                color = RRTAndODTFit(color);

                color = mul(ACESOutputMat, color);

                color = saturate(color);
                
                return color;
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                // sample the texture
                half4 col = tex2D(_MainTex, i.uv);

                col.rgb = ACESFitted(col.rgb);

                return col;
            }
            ENDCG
        }
    }
}

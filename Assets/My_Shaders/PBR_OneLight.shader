Shader "PBR"
{
    Properties
    {
        [Toggle(_RECEIVE_SHADOW)] _RECEIVE_SHADOW("receive shadow", float) = 0

        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("BaseColor", Color) = (1,1,1,1)

        _Metallic("Metallic Scale", Range(0.0001,1)) = 0.0001
        _Roughness("Roughness", Range(0.0001,1)) = 0.5

        [Toggle(_NORMALMAP)] _NormalMap("Open Normal Map?", float) = 0
        _BumpScale("Normal Scale", float) = 1.0
        [Normal] _BumpMap("Normal Map", 2D) = "bump" {}

        //[HideInInspector][NoScaleOffset]unity_Lightmaps("unity_Lightmaps", 2DArray) = "" {}
        //[HideInInspector][NoScaleOffset]unity_LightmapsInd("unity_LightmapsInd", 2DArray) = "" {}
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "MyForwardPass"
            Tags{"LightMode" = "UniversalForward"}

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            //材质关键词
            #pragma shader_feature _RECEIVE_SHADOW  //开启接受阴影
            #pragma shader_feature _NORMALMAP       //使用法线贴图
            #pragma shader_feature _EMISSION        //开启自发光
            //渲染流水线关键词
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN     //主光开启投射阴影
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT           //开启软阴影

            // #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 vertex : POSITION;    //模型空间顶点坐标
                float3 normal : NORMAL;      //模型空间法向量
                float4 tangent: TANGENT;     //模型空间切向量
                float2 uv     : TEXCOORD0;
            };

            struct Varyings
            {
                float4 pos       : SV_POSITION;  //齐次裁剪空间顶点坐标
                float2 uv        : TEXCOORD0;    //纹理坐标
                float3 normalWS  : TEXCOORD1;    //世界空间法线
                float3 viewDirWS : TEXCOORD2;    //世界空间视线方向
                float3 posWS: TEXCOORD3;         //世界空间顶点位置

                //DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 4);    //声明光照贴图的纹理坐标，光照贴图名称、球谐光照名称、纹理坐标索引

                #ifdef _NORMALMAP
                    float4 tangentWS: TEXCOORD5;            //xyz是世界空间切向量，w是方向
                #endif

                half4 fogFactorAndVertexLight: TEXCOORD6;    //x是雾系数，yzw为顶点光照
            };

            CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half _Roughness;
            half _Metallic;
            half _BumpScale;
            CBUFFER_END

            TEXTURE2D(_BaseMap);    
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_BumpMap);    
            SAMPLER(sampler_BumpMap);

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);       //获得各个空间下的顶点坐标
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal, v.tangent);    //获得各个空间下的法线切线坐标
                float3 viewDirWS = GetCameraPositionWS() - vertexInput.positionWS;              //世界空间视线方向=世界空间相机位置-世界空间顶点位置
                half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);   //遍历灯光做逐顶点光照（考虑了衰减）
                half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);   //获得纹理坐标
                o.normalWS = normalInput.normalWS;
                o.viewDirWS = viewDirWS;

                #ifdef _NORMALMAP
                    real sign = v.tangent.w * GetOddNegativeScale();
                    o.tangentWS = half4(normalInput.tangentWS.xyz, sign);
                #endif

                o.fogFactorAndVertexLight = half4(fogFactor, vertexLight);  //计算雾效

                o.posWS = vertexInput.positionWS;

                o.pos = vertexInput.positionCS;    //齐次裁剪空间顶点坐标
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                //初始化视线
                half3 viewDirWS = SafeNormalize(i.viewDirWS);
                //初始化法线
                #ifdef _NORMALMAP
                    half4 n = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv);
                    half3 normalTS = UnpackNormalScale(n, _BumpScale);
                    float sgn = i.tangentWS.w;      // should be either +1 or -1
                    float3 bitangent = sgn * cross(i.normalWS.xyz, i.tangentWS.xyz);     //副切线
                    half3x3 tangentToWorld = half3x3(i.tangentWS.xyz, bitangent.xyz, i.normalWS.xyz);   //TBN矩阵
                    i.normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
                #else
                    i.normalWS = i.normalWS;
                #endif
                i.normalWS = NormalizeNormalPerPixel(i.normalWS);

                //获得主光源信息
#ifdef _RECEIVE_SHADOW
                float4 shadowCoord = TransformWorldToShadowCoord(i.posWS);
                Light mainLight = GetMainLight(shadowCoord);      //获取带阴影的主光源
#else
                Light mainLight = GetMainLight();
#endif
                float3 lightDir = normalize(mainLight.direction);//主光源方向
                
                float4 albedoAlpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);      //非导体反照率颜色=baseColor+高光反射颜色
                float3 albedo = albedoAlpha.rgb * _BaseColor.rgb;

                //金属粗糙度工作流
                //初始化金属度粗糙度
                half metallic = _Metallic;
                half roughness = 1 - _Roughness;
                
                half3 H = normalize(viewDirWS + lightDir);     //半向量
                float VoH = max(0.001, saturate(dot(viewDirWS, H)));
                float NoV = max(0.001, saturate(dot(i.normalWS, viewDirWS)));
                float NoL = max(0.001, saturate(dot(i.normalWS, lightDir)));
                float NoH = saturate(dot(i.normalWS, H));

                half3 radiance = mainLight.color * mainLight.shadowAttenuation  * mainLight.distanceAttenuation * NoL;     //获取光强

                half3 F0 = lerp(half3(0.04, 0.04, 0.04), albedo, metallic);   //F0就是 brdfSpecular，half3(0.04, 0.04, 0.04)是非金属的 F0典型值
                //其实 0.04是由 0.08 * SpecularScale获得的，而 SpecularScale默认值为 0.5

                //菲涅尔项 F Schlick Fresnel
                float3 F_Schlick = F0 + (1 - F0) * pow(1 - VoH, 5.0);
                float3 Kd = (1 - F_Schlick) * (1 - metallic);
                float3 brdfDiffuse = albedo * Kd;

                //lambert diffuse 
                // float3 diffuseColor = brdfDiffuse * mainLight.color * NoL;
                float3 diffuseColor = brdfDiffuse * radiance;

                //法线分布项 D NDF GGX
                float a = roughness * roughness;
                float a2 = a * a;
                float d = (NoH * a2 - NoH) * NoH + 1;
                float D_GGX = a2 / (PI * d * d);

                //几何项 G
                float k = (roughness + 1) * (roughness + 1) / 8;
                float GV = NoV / (NoV * (1 - k) + k);
                float GL = NoL / (NoL * (1 - k) + k);
                float G_GGX = GV * GL;

                float3 brdf = F_Schlick * D_GGX * G_GGX / (4 * NoV * NoL);
                float3 specularColor = brdf * radiance * PI;

                half3 color = diffuseColor + specularColor;

                return float4(color, 1);
            }
            ENDHLSL
        }
    }
}
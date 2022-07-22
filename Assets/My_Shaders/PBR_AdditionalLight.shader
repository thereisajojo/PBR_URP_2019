Shader "PBR_AdditionalLight"
{
    Properties
    {
        [Toggle(_RECEIVE_SHADOW)] _RECEIVE_SHADOW("receive shadow", float) = 0

        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("BaseColor", Color) = (1,1,1,1)

        [Toggle(_USE_METALLICMAP)] _UseMetallicMap("Use Metallic Map?", float) = 0
        _MetallicMap("Metallic Texture", 2D) = "white" {}
        _Metallic("Metallic Scale", Range(0.0001,1)) = 0.0001
        _Roughness("Roughness", Range(0.0001,1)) = 0.5

        [Toggle(_NORMALMAP)] _NormalMap("Open Normal Map?", float) = 0
        _BumpScale("Normal Scale", float) = 1.0
        [Normal] _BumpMap("Normal Texture", 2D) = "bump" {}

        [Toggle(_EMISSION)] _Emisssion("Emission", float) = 0
        _EmissionMap("Emission Texture", 2D) = "Black"{}
        [HDR]_EmissionColor("Emission Color", Color) = (0,0,0,0)

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
            #pragma shader_feature _USE_METALLICMAP //使用金属度贴图
            #pragma shader_feature _EMISSION        //开启自发光
            //渲染流水线关键词
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN     //主光开启投射阴影
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT   //开启软阴影

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 vertex    : POSITION;
                float3 normal    : NORMAL;
                float4 tangent   : TANGENT;
                float2 uv        : TEXCOORD0;
            };

            struct Varyings
            {
                float4 pos       : SV_POSITION;
                float2 uv        : TEXCOORD0;
                float3 normalWS  : TEXCOORD1;
                float3 viewDirWS : TEXCOORD2;
                float3 posWS     : TEXCOORD3;

                //DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 4);    //声明光照贴图的纹理坐标，光照贴图名称、球谐光照名称、纹理坐标索引

                #ifdef _NORMALMAP
                    float4 tangentWS: TEXCOORD5;
                #endif

                half4 fogFactorAndVertexLight: TEXCOORD6;    //x是雾系数，yzw为顶点光照
            };

            CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half _Roughness;
            half _Metallic;
            half _BumpScale;
            half4 _EmissionColor;
            CBUFFER_END

            TEXTURE2D(_BaseMap);    
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_BumpMap);    
            SAMPLER(sampler_BumpMap);

            TEXTURE2D(_MetallicMap);    
            SAMPLER(sampler_MetallicMap);

            TEXTURE2D(_EmissionMap);    
            SAMPLER(sampler_EmissionMap);

            struct VectorDot
            {
                float VoH;
                float NoV;
                float NoL;
                float NoH;
            };

            void InitializeVectorDot(float3 viewDirWS, float3 normalWS, float3 lightDir, out VectorDot VDot)
            {
                VDot = (VectorDot)0;
                float3 H = normalize(viewDirWS + lightDir); //半向量
                VDot.VoH = max(0.001, saturate(dot(viewDirWS, H)));
                VDot.NoV = max(0.001, saturate(dot(normalWS, viewDirWS)));
                VDot.NoL = max(0.001, saturate(dot(normalWS, lightDir)));
                VDot.NoH = saturate(dot(normalWS, H));
            }

            half3 DirectLight(VectorDot VDot, half3 albedo, float metallic, float roughness, half3 attenuatedLightColor)
            {
                float VoH = VDot.VoH;
                float NoV = VDot.NoV;
                float NoL = VDot.NoL;
                float NoH = VDot.NoH;

                half3 radiance = attenuatedLightColor * NoL;     //获取光强(辐射率)

                half3 F0 = lerp(half3(0.04, 0.04, 0.04), albedo, metallic);   //F0就是 brdfSpecular，half3(0.04, 0.04, 0.04)是非金属的 F0典型值

                //菲涅尔项 F Schlick Fresnel
                float3 F_Schlick = F0 + (1 - F0) * pow(1 - VoH, 5.0);
                float3 Kd = (1 - F_Schlick) * (1 - metallic);
                float3 brdfDiffuse = albedo * Kd;

                //lambert diffuse 
                // float3 diffuseColor = brdfDiffuse * mainLight.color  * NoL;
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

                return color;
            }

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);       //获得各个空间下的顶点坐标
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal, v.tangent);    //获得各个空间下的法线切线坐标
                float3 viewDirWS = GetCameraPositionWS() - vertexInput.positionWS;              //世界空间视线方向=世界空间相机位置-世界空间顶点位置
                //half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);   //遍历灯光做逐顶点光照（考虑了衰减）
                //half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);   //获得纹理坐标
                o.normalWS = normalInput.normalWS;
                o.viewDirWS = viewDirWS;

                #ifdef _NORMALMAP
                    real sign = v.tangent.w * GetOddNegativeScale();
                    o.tangentWS = half4(normalInput.tangentWS.xyz, sign);
                #endif

                //o.fogFactorAndVertexLight = half4(fogFactor, vertexLight);  //计算雾效

                o.posWS = vertexInput.positionWS;

                o.pos = vertexInput.positionCS;    //齐次裁剪空间顶点坐标
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                //初始化视线
                float3 viewDirWS = SafeNormalize(i.viewDirWS);
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
                
                float4 albedoAlpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                float3 albedo = albedoAlpha.rgb * _BaseColor.rgb;

                //金属粗糙度工作流
                //初始化金属度粗糙度
                half metallic;
                half roughness;

                #ifdef _USE_METALLICMAP
                    half4 metallicTex = SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, i.uv);
                    metallic = metallicTex.r;
                    roughness = metallicTex.a * _Roughness;
                #else
                    metallic = _Metallic;
                    roughness = _Roughness;
                #endif

                roughness = 1 - roughness;
                
                VectorDot VDot;
                InitializeVectorDot(viewDirWS, i.normalWS, lightDir, VDot);

                //直接光照
                half3 attenuatedMainLightColor = mainLight.color * mainLight.shadowAttenuation * mainLight.distanceAttenuation;
                half3 color = DirectLight(VDot, albedo, metallic, roughness, attenuatedMainLightColor);

                //多光源
                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
                {
                    Light light = GetAdditionalLight(lightIndex, i.posWS);

                    VectorDot VDot_new;
                    InitializeVectorDot(viewDirWS, i.normalWS, light.direction, VDot_new);

                    half3 attenuatedLightColor = light.color * light.shadowAttenuation * light.distanceAttenuation;

                    color += DirectLight(VDot_new, albedo, metallic, roughness, attenuatedLightColor);
                }

                //自发光
                #ifdef _EMISSION
                    color += SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, i.uv).rgb * _EmissionColor.rgb;
                #endif

                return half4(color, 1);
            }
            ENDHLSL
        }
    }
}
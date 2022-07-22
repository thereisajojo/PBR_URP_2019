Shader "PBR_IndirectLight"
{
    Properties
    {
        [Toggle(_RECEIVE_SHADOW)] _RECEIVE_SHADOW("receive shadow", float) = 0

        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("BaseColor", Color) = (1,1,1,1)

        [Toggle(_USE_METALLICMAP)] _UseMetallicMap("Use Metallic Map?", float) = 0
        _MetallicMap("Metallic Texture", 2D) = "white" {}
        [Gamma] _Metallic("Metallic Scale", Range(0.0001,1)) = 0.0001
        _Roughness("Roughness", Range(0.0001,1)) = 0.5

        [Toggle(_NORMALMAP)] _NormalMap("Open Normal Map?", float) = 0
        _BumpScale("Normal Scale", float) = 1.0
        [Normal] _BumpMap("Normal Texture", 2D) = "bump" {}

        [Toggle(_EMISSION)] _Emisssion("Emission", float) = 0
        _EmissionMap("Emission Texture", 2D) = "Black"{}
        [HDR]_EmissionColor("Emission Color", Color) = (0,0,0,0)

        _IrradianceMap("Irradiance Map", Cube) = "white"{}
        _LUT("LUT", 2D) = "white" {}

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

            //材质关键字
            #pragma shader_feature _RECEIVE_SHADOW  //开启接受阴影
            #pragma shader_feature _NORMALMAP       //使用法线贴图
            #pragma shader_feature _USE_METALLICMAP //使用金属度贴图
            #pragma shader_feature _EMISSION        //开启自发光
            //渲染管线关键字
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS  //多光源
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN   //主光开启投射阴影
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

            TEXTURE2D(_LUT);    
            SAMPLER(sampler_LUT);

            TEXTURECUBE(_IrradianceMap);    
            SAMPLER(sampler_IrradianceMap);

            struct VectorDot
            {
                float VoH;
                float NoV;
                float NoL;
                float NoH;
                float HoL;
            };

            void InitializeVectorDot(float3 viewDirWS, float3 normalWS, float3 lightDir, out VectorDot VecDot)
            {
                float3 H = normalize(viewDirWS + lightDir); //半向量
                VecDot.VoH = max(0.0001, (dot(viewDirWS, H)));
                VecDot.NoV = max(0.0001, (dot(normalWS, viewDirWS)));
                VecDot.NoL = max(0.0001, (dot(normalWS, lightDir)));
                VecDot.NoH = max(0.0001, (dot(normalWS, H)));
                VecDot.HoL = max(0.0001, (dot(H, lightDir)));
            }

            //====== 直接光照函数 ======
            half3 DirectLight(half3 F0, VectorDot VecDot, half3 albedo, float metallic, float roughness, half3 attenuatedLightColor, out float3 brdf)
            {
                float VoH = VecDot.VoH;
                float NoV = VecDot.NoV;
                float NoL = VecDot.NoL;
                float NoH = VecDot.NoH;
                float HoL = VecDot.HoL;

                half3 radiance = attenuatedLightColor * NoL;     //获取光强(辐射率)

                //菲涅尔项 F Schlick Fresnel
                float3 F_Schlick = F0 + (1 - F0) * pow(1 - HoL, 5.0);//原式为NoH，unity优化为HoL
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

                brdf = F_Schlick * D_GGX * G_GGX / (4 * NoV * NoL);
                float3 specularColor = brdf * radiance * PI;

                half3 color = diffuseColor + specularColor;

                return color;
            }

            //====== 间接光函数 ======

            //漫反射
            half3 my_SampleSH9(half4 SHCoefficients[7], half3 N)
            {
                half4 shAr = SHCoefficients[0];
                half4 shAg = SHCoefficients[1];
                half4 shAb = SHCoefficients[2];
                half4 shBr = SHCoefficients[3];
                half4 shBg = SHCoefficients[4];
                half4 shBb = SHCoefficients[5];
                half4 shCr = SHCoefficients[6];

                // Linear + constant polynomial terms
                half3 res = SHEvalLinearL0L1(N, shAr, shAg, shAb);

                // Quadratic polynomials
                res += SHEvalLinearL2(N, shBr, shBg, shBb, shCr);

                return res;
            }

            // Samples SH L0, L1 and L2 terms
            half3 my_SampleSH(half3 normalWS)
            {
                // LPPV is not supported in Ligthweight Pipeline
                half4 SHCoefficients[7];
                SHCoefficients[0] = unity_SHAr;
                SHCoefficients[1] = unity_SHAg;
                SHCoefficients[2] = unity_SHAb;
                SHCoefficients[3] = unity_SHBr;
                SHCoefficients[4] = unity_SHBg;
                SHCoefficients[5] = unity_SHBb;
                SHCoefficients[6] = unity_SHC;

                return max(half3(0, 0, 0), my_SampleSH9(SHCoefficients, normalWS));
            }

            //镜面反射
            //F项间接光,加入粗糙度
            half3 Indir_F_Function(float NdotV,float3 F0,float roughness)
            {
                return F0 + (max(float3(1, 1, 1) * (1.0 - roughness), F0) - F0) * pow(1.0 - NdotV, 5.0);
                //float  Fre=exp2((-5.55473*NdotV-6.98316)*NdotV);
                //return  F0+Fre*saturate(1-roughness-F0);
            }

            //反射探针+skybox
            half3 IndirectSpeCube(half3 normalWS, half3 viewDirWS, float roughness)
            {
                float3 reflectDirWS = reflect(-viewDirWS, normalWS);
                roughness = roughness * (1.7 - 0.7 * roughness); //unity 内部不是线性 调整下 拟合曲线求近似
                float mipLevel = roughness * UNITY_SPECCUBE_LOD_STEPS;
                half4 specularColor = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectDirWS, mipLevel);
                #if !defined(UNITY_USE_NATIVE_HDR)
                    return DecodeHDREnvironment(specularColor, unity_SpecCube0_HDR);
                #else
                    return specularColor.rgb;
                #endif
            }

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);       //获得各个空间下的顶点坐标
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal, v.tangent);    //获得各个空间下的法线切线坐标
                float3 viewDirWS = GetCameraPositionWS() - vertexInput.positionWS;              //世界空间视线方向=世界空间相机位置-世界空间顶点位置
                //half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);   //遍历灯光做逐顶点光照（考虑了衰减）
                //half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                o.uv = TRANSFORM_TEX(v.uv, _BaseMap); //获得纹理坐标
                o.normalWS = normalInput.normalWS;
                o.viewDirWS = viewDirWS;

                #ifdef _NORMALMAP
                    real sign = v.tangent.w * GetOddNegativeScale();
                    o.tangentWS = half4(normalInput.tangentWS.xyz, sign);
                #endif

                //o.fogFactorAndVertexLight = half4(fogFactor, vertexLight);  //计算雾效

                o.posWS = vertexInput.positionWS;

                o.pos = vertexInput.positionCS;
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

                //====== 直接光照部分 ======

                //获得主光源信息
                #ifdef _RECEIVE_SHADOW
                    float4 shadowCoord = TransformWorldToShadowCoord(i.posWS);
                    Light mainLight = GetMainLight(shadowCoord); //获取带阴影的主光源
                #else
                    Light mainLight = GetMainLight();
                #endif

                float3 lightDir = normalize(mainLight.direction); //主光源方向
                
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
                //roughness = roughness * roughness;

                half3 F0 = lerp(half3(0.04, 0.04, 0.04), albedo, metallic); //F0就是 brdfSpecular，half3(0.04, 0.04, 0.04)是非金属的 F0典型值
                
                //计算各个向量间的点乘
                VectorDot VecDot;
                InitializeVectorDot(viewDirWS, i.normalWS, lightDir, VecDot);

                //主光源光照
                half3 BRDF;
                half3 attenuatedMainLightColor = mainLight.color * mainLight.shadowAttenuation * mainLight.distanceAttenuation;
                half3 color = DirectLight(F0, VecDot, albedo, metallic, roughness, attenuatedMainLightColor, BRDF);

                //多光源
                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
                {
                    Light light = GetAdditionalLight(lightIndex, i.posWS);

                    VectorDot VDot_new;
                    InitializeVectorDot(viewDirWS, i.normalWS, light.direction, VDot_new);

                    #ifdef _RECEIVE_SHADOW
                        half3 attenuatedLightColor = light.color * light.shadowAttenuation * light.distanceAttenuation;
                    #else
                        half3 attenuatedLightColor = light.color * light.distanceAttenuation;
                    #endif

                    half3 brdf_addLight;
                    color += DirectLight(F0, VDot_new, albedo, metallic, roughness, attenuatedLightColor, brdf_addLight);
                }

                //自发光
                #ifdef _EMISSION
                    color += SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, i.uv).rgb * _EmissionColor.rgb;
                #endif

                //============ 间接光照部分 ============

                //====== 间接光漫反射 ======
                //half3 SHColor = my_SampleSH(i.normalWS);//采样Light Probe
                half3 SHColor = SAMPLE_TEXTURECUBE(_IrradianceMap, sampler_IrradianceMap, i.normalWS).rgb;//辐照度
                half3 IndirectKs = Indir_F_Function(VecDot.NoV, F0, roughness);
                half3 IndirectKd = (1 - IndirectKs) * (1 - metallic);
                half3 IndirectDiffuseColor = IndirectKd * SHColor * albedo;

                //====== 镜面反射 ======
                half3 IndirectSpeCubeColor = IndirectSpeCube(i.normalWS, viewDirWS, roughness);//环境贴图

                /*
                //===unity源代码中的方法===
                half surfaceReduction = 1.0 / (roughness * roughness + 1);
                half reflectivity = 0.04 + (metallic * 0.96);//反射率
                half grazingTerm = saturate(1 - roughness + reflectivity);
                half fresnelTerm = Pow4(1.0 - saturate(dot(i.normalWS, viewDirWS)));
                half3 IndirectSpeColor = surfaceReduction * IndirectSpeCubeColor * lerp(F0, grazingTerm, fresnelTerm);
                */

                //===LUT预积分方法===
                half3 F = IndirectKs;
                float2 envBRDF = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, float2(VecDot.NoV, roughness)).rg;
                half3 IndirectSpeColor = IndirectSpeCubeColor * (F * envBRDF.x + envBRDF.y);

                //====== 镜面反射结束 ======

                half3 IndirectColor = IndirectDiffuseColor + IndirectSpeColor;

                //============ 间接光照部分结束 ============

                color += IndirectColor;

                return half4(color, 1);
            }
            ENDHLSL
        }
    }
}
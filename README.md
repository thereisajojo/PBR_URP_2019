# PBR_URP_2019
 unity2019.4.9f1

参考LearningOpenGL的PBR实现方式，地址：https://learnopengl-cn.github.io/07%20PBR/01%20Theory/

项目设置：
1.使用urp管线
2.颜色空间设置为Linear
3.Asset-->Setting-->ForwardRenderer中添加名为ToneMapRenderPassFeature的renderfeature，以启用HDR色调映射后处理

项目说明：
1.直接光照：平行光+多光源+阴影

2.间接光照--漫反射：2.1 利用环境贴图CubeMap预计算积分获得辐照度图（Irradiance Map），然后在shader中采样
                  2.2 直接调用Unity接口：球谐函数SampleSH()
                  2.3 自己重新实现球谐函数（正在开发中）

3.间接光照--镜面反射：3.1 预滤波环境贴图使用unity自带的unity_SpecCube0；
                    3.2 brdf积分部分：3.2.1 参考Lighting.hlsl源码，数字化处理镜面高光，不做积分。
                                     3.2.2 预计算brdf值（离散积分，用Hammersley低差异序列做GGX重要性采样），保存在LUT贴图中，最后shader里采样

4.编辑器工具：1.“Tools/Create BRDF_LUT”：预计算BRDF积分
             2.“Tools/IBL 辐照度预积分”：利用环境贴图CubeMap计算生成辐照度图，生成的图要将格式从2D改为Cube，关闭sRGB选项。

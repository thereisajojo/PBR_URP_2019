using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class ToneMapRenderPassFeature : ScriptableRendererFeature
{
    public Shader shader;
    class ToneMapRenderPass : ScriptableRenderPass
    {
        private RenderTargetIdentifier source;
        private RenderTargetHandle tempTargetHandle;
        private Material material;

        public ToneMapRenderPass()
        {
            tempTargetHandle.Init("tempToneMapping");
        }

        public void Setup(RenderTargetIdentifier source, Shader shader)
        {
            this.source = source;
            material = new Material(shader);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("ToneMappingCmd");
            var dec = renderingData.cameraData.cameraTargetDescriptor;
            dec.msaaSamples = 1;
            dec.depthBufferBits = 0;
            cmd.GetTemporaryRT(tempTargetHandle.id, dec);

            cmd.Blit(source, tempTargetHandle.Identifier(), material);
            cmd.Blit(tempTargetHandle.Identifier(), source);
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
            cmd.ReleaseTemporaryRT(tempTargetHandle.id);
        }
    }

    ToneMapRenderPass toneMapRenderPass;

    /// <inheritdoc/>
    public override void Create()
    {
        toneMapRenderPass = new ToneMapRenderPass();

        // Configures where the render pass should be injected.
        toneMapRenderPass.renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(toneMapRenderPass);
        toneMapRenderPass.Setup(renderer.cameraColorTarget, shader);
    }
}
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class CustomRenderPassFeature : ScriptableRendererFeature
{
    class CustomRenderPass : ScriptableRenderPass
    {
        static string rt_name = "_MainTex";
        static int rt_ID = Shader.PropertyToID(rt_name);

        // 寻找shader
        static string blitShader_Name = "Example/BlitShader";
        static Shader blitShader = Shader.Find(blitShader_Name);
        private Material blitMaterial = new Material(blitShader);
        
        
        // private int id = Shader.PropertyToID("_MainTex");
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 帮助Execute() 提前准别它所需要的 RenderTexture 或者 其他的变量
            RenderTextureDescriptor descriptor = new RenderTextureDescriptor(2560,1440,RenderTextureFormat.Default,0);
            cmd.GetTemporaryRT(rt_ID,descriptor);
            ConfigureTarget(rt_ID);
            // ConfigureClear(ClearFlag.Color,Color.black);
            
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            // 实现这个RenderPass做什么事情
            CommandBuffer cmd = CommandBufferPool.Get("tmpCmd");
            cmd.Blit(renderingData.cameraData.renderer.cameraColorTarget,rt_ID,blitMaterial);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            cmd.Release();
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            // 释放在OnCameraSetup() 里声明的变量
            // 尤其是TemporaryRenderTexture
        }
    }

    CustomRenderPass m_ScriptablePass;

    public override void Create()
    {
        m_ScriptablePass = new CustomRenderPass();
        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }
}
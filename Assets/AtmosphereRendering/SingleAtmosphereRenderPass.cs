using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


public class SingleAtmosphereRenderPass: ScriptableRenderPass{
        const string customPassTag = "SingleAtmosphereRenderPass";
        //当前阶段渲染的颜色RT
        private RenderTargetIdentifier src;
        //辅助RT
        private RenderTargetHandle dst;
        private SingleAtmosphereVolume parameters;
        private Material mat;
        //Profiling上显示
        ProfilingSampler m_ProfilingSampler = new ProfilingSampler("URPTest");
        
        public void Setup(RenderTargetIdentifier src,Material mat){
            this.src = src;
            this.mat = mat;
            if (this.mat == null){
                Debug.Log("Material is Null");
            }
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData data){

            VolumeStack stack = VolumeManager.instance.stack;
            parameters = stack.GetComponent<SingleAtmosphereVolume>();
            CommandBuffer command = CommandBufferPool.Get(customPassTag);
            //using的做法就是可以在FrameDebug上看到里面的所有渲染
            using(new ProfilingScope(command,m_ProfilingSampler)){
                Render(command, ref data);
            }
            context.ExecuteCommandBuffer(command);
            CommandBufferPool.Release(command);
            command.ReleaseTemporaryRT(dst.id);
        }
        public void Render(CommandBuffer command, ref RenderingData data){
            if(parameters.IsActive()){
                parameters.load(mat, ref data);
                RenderTextureDescriptor opaqueDesc = data.cameraData.cameraTargetDescriptor;
                opaqueDesc.depthBufferBits = 0;
                command.GetTemporaryRT(dst.id, opaqueDesc);
                command.Blit(src, dst.Identifier(), mat);
                command.Blit(dst.Identifier(), src);
            }
        }
    }
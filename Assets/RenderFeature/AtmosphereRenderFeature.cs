using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace XinYi
{
    public class AtmosphereRenderFeature : ScriptableRendererFeature
    {

        [SerializeField] private Shader shader;
        [SerializeField] private RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        [SerializeField] private GameObject container;
        private Material matInstance;   //创建一个该Shader的材质对象
        private AtmosphereRenderPass pass;

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData){
            if(container != null)
                Debug.Log(container.transform.position);
            //shader与材质的固定搭配：当二者非空时，调用CoreUtils.CreateEngineMaterial()
            if(shader == null)return;
            if(matInstance == null){
                matInstance = CoreUtils.CreateEngineMaterial(shader);
            }
            RenderTargetIdentifier currentRT = renderer.cameraColorTarget;
            pass.Setup(currentRT, matInstance,container);
            renderer.EnqueuePass(pass);
        }
        public override void Create(){
            pass = new AtmosphereRenderPass();
            pass.renderPassEvent = passEvent;
        }
    }

    public class AtmosphereRenderPass : ScriptableRenderPass
    {
        private const string passTag = "VolumetricClouds";
        private AtmosphereVolume parameters;
        private Material passMaterial;
        private GameObject container;

        private RenderTargetIdentifier sourceRT;
        private RenderTargetHandle tempRT; //临时Render Target
        //private RenderTextureDescriptor renderTextureDescriptor;

        public void Setup(RenderTargetIdentifier identifier, Material material , GameObject obj)
        {
            this.sourceRT = identifier;
            this.passMaterial = material;
            this.container = obj;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData data)
        {

            VolumeStack stack = VolumeManager.instance.stack; //获取全局后处理实例栈
            parameters = stack.GetComponent<AtmosphereVolume>(); //获取扩展Volume组件
            CommandBuffer command = CommandBufferPool.Get(passTag);
            Render(command, ref data);
            context.ExecuteCommandBuffer(command);
            CommandBufferPool.Release(command);
            command.ReleaseTemporaryRT(tempRT.id);
        }
        public void Render(CommandBuffer command, ref RenderingData data)
        {

            if (parameters.IsActive())
            {
                parameters.load(passMaterial, ref data);
                /*if(container != null){
                    Transform transform = container.transform;
                    passMaterial.SetVector("_BoundMin", new Vector4(-50,-50,-50,0));
                    passMaterial.SetVector("_BoundMax", new Vector4(50,50,50,0));
                }*/
                RenderTextureDescriptor opaqueDesc = data.cameraData.cameraTargetDescriptor;
                opaqueDesc.depthBufferBits = 0;
                command.GetTemporaryRT(tempRT.id, opaqueDesc);
                command.Blit(sourceRT, tempRT.Identifier(), passMaterial);
                command.Blit(tempRT.Identifier(), sourceRT);
            }
        }
    }
}
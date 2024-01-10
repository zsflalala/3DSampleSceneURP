using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class Dualblur : ScriptableRendererFeature
{
    [System.Serializable]
    public class mysetting
    {
        public RenderPassEvent passEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material mymat;
        [Range(1,8)] public int downsample = 2;
        [Range(2,8)] public int loop = 2;
        [Range(0.5f,5f)] public float blur = 0.5f;
        public string RenderFeatureName = "我的双重Kawase模糊";
    }
    public mysetting setting = new mysetting();
    // 自定义Pass
    class CustomRenderPass : ScriptableRenderPass
    {
        public Material passMat = new Material(Shader.Find("ShengFu/DualBlur"));
        public int passdownsample = 2; // 降采样
        public int passloop = 2; // 模糊的迭代次数
        public float passblur = 4;
        private RenderTargetIdentifier passSource{get;set;}
        RenderTargetIdentifier buffer1; // RTa1的ID
        RenderTargetIdentifier buffer2; // RTa2的ID
        string RenderFeatherName;       // feather名
        struct LEVEL
        {
            public int down;
            public int up;
        }
        LEVEL[] my_level;
        int maxLevel = 16; // 指定一个最大值来限制申请的ID的数量，这里限制16个，肯定用不完
        public CustomRenderPass(string name){ // 构造函数
            RenderFeatherName = name;
        }
        public void setup(RenderTargetIdentifier sour){ // 初始化，接收render feather传的图
            this.passSource = sour;
            my_level = new LEVEL[maxLevel];
            for (int t = 0;t < maxLevel;t++){
                my_level[t] = new LEVEL{
                    down = Shader.PropertyToID("_BlurMipDown"+t),
                    up = Shader.PropertyToID("_BlurMipUp"+t)
                };
            }
        }
        
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 帮助Execute() 提前准别它所需要的 RenderTexture 或者 其他的变量
            RenderTextureDescriptor descriptor = new RenderTextureDescriptor(2560,1440,RenderTextureFormat.Default,0);
            // ConfigureClear(ClearFlag.Color,Color.black);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            // 实现这个RenderPass做什么事情
            CommandBuffer cmd = CommandBufferPool.Get(RenderFeatherName); // 定义cmd
            // passMat.SetFloat("_Blur",passblur); // 指定材质参数
            // cmd.SetGlobalFloat("_Blur",passblur); // 设置模糊，但是不想全局设置，怕影响到其他的shader，所以注销了用上面的，但是cmd这个性能可能好些？
            RenderTextureDescriptor opaquedesc = renderingData.cameraData.cameraTargetDescriptor; // 定义品目图像参数结构体
            int width = opaquedesc.width / passdownsample; // 第一次降采样是使用的参数，后面就是除2去降采样
            int height = opaquedesc.height / passdownsample;
            opaquedesc.depthBufferBits = 0;
            // down
            RenderTargetIdentifier LastDown = passSource; // 把初始图像作为lastdown的起始图像去计算
            for (int t = 0;t < passloop;t++){
                int midDown = my_level[t].down; // middle down 间接计算down的工具人ID
                int midUp = my_level[t].up;     // middle up   间接计算的up工具人ID
                cmd.GetTemporaryRT(midDown,width,height,0,FilterMode.Bilinear,RenderTextureFormat.ARGB32);
                cmd.GetTemporaryRT(midUp,width,height,0,FilterMode.Bilinear,RenderTextureFormat.ARGB32);
                cmd.Blit(LastDown,midDown,passMat,0);
                LastDown = midDown;             // 工具人辛苦了
                width = Mathf.Max(width / 2,1); // 每次循环都降尺寸
            }
            // up
            int lastUp = my_level[passloop - 1].down; // 把down的最后一次图像当成up的第一次图去计算up
            for (int j = passloop - 2;j >= 0;j--){
                int midUp = my_level[j].up;
                cmd.Blit(lastUp,midUp,passMat,1);     // 在down的过程中已经把RT的位置霸占好了，直接使用
                lastUp = midUp;  // 工具人辛苦了
            }
            cmd.Blit(lastUp,passSource,passMat,1); // 补一次up，顺便输出
            context.ExecuteCommandBuffer(cmd);     // 执行缓冲区的命令
            for (int k = 0; k < passloop;k++){     // 清RT，防止内存泄漏
                cmd.ReleaseTemporaryRT(my_level[k].up);
                cmd.ReleaseTemporaryRT(my_level[k].down);
            }
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            // 释放在OnCameraSetup() 里声明的变量
            // 尤其是TemporaryRenderTexture
        }
    }

    CustomRenderPass mypass;

    public override void Create()
    {
        mypass = new CustomRenderPass(setting.RenderFeatureName); // 实例化一下并传参数,name就是tag
        mypass.renderPassEvent = setting.passEvent;
        mypass.passblur = setting.blur;
        mypass.passloop = setting.loop;
        mypass.passMat  = setting.mymat;
        mypass.passdownsample = setting.downsample;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData) // 传值到pass里
    {
        mypass.setup(renderer.cameraColorTarget);
        renderer.EnqueuePass(mypass);
    }
}
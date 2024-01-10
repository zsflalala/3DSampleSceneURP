using UnityEngine;
using UnityEngine.Rendering;

public class CameraRenderer
{
    ScriptableRenderContext context;
    Camera camera;
    public void Render(ScriptableRenderContext context,Camera camera){
        this.context = context;
        this.camera = camera;
    }
}

public class CustomRenderPipeline : RenderPipeline 
{
    CameraRenderer renderer = new CameraRenderer();
    protected override void Render (ScriptableRenderContext context, Camera[] cameras) 
    {
        for (int i = 0;i < Camera.allCamerasCount;i++){
            renderer.Render(context,cameras[i]);
        }
    }
}
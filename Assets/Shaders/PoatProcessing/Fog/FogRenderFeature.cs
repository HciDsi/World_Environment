using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[Serializable]
[VolumeComponentMenuForRenderPipeline("World/Fog", typeof(UniversalRenderPipeline))]
public class Fog : VolumeComponent, IPostProcessComponent
{
    [Tooltip("")]
    public ClampedFloatParameter FogDensity = new ClampedFloatParameter(0.5f, 0.0f, 1.0f);
    [Tooltip("")]
    public ColorParameter FogColor = new ColorParameter(Color.red);

    public bool IsActive() => FogDensity.value != 0;

    public bool IsTileCompatible() => false;
}

public class FogPass : ScriptableRenderPass
{
    static readonly string renderTargets = "Post Fog Pass";

    static readonly int MainTexId = Shader.PropertyToID("_MainTex");
    static readonly int TempTargetId = Shader.PropertyToID("_TempTarget");

    Fog val;
    Material mate;
    Transform transform;
    RenderTargetIdentifier currTarget;

    public FogPass(RenderPassEvent evt)
    {
        renderPassEvent = evt;

        Shader shader = Shader.Find("PostProcessing/Fog");
        if(shader == null)
        {
            Debug.LogError("Not Find Shader " + renderTargets);
            return;
        }
        mate = CoreUtils.CreateEngineMaterial(shader);

        transform = GameObject.Find("FogBox").transform;
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if(mate == null)
        {
            Debug.LogError("Not Create Material " + renderTargets);
            return;
        }
        if(transform == null)
        {
            Debug.LogError("Not Create FogBox ");
            return;
        }

        if(!renderingData.cameraData.postProcessEnabled)
        {
            return;
        }

        var stack = VolumeManager.instance.stack;
        val = stack.GetComponent<Fog>();
        if(val != null && val.IsActive())
        {
            CommandBuffer cmd = CommandBufferPool.Get(renderTargets);
            Render(cmd, ref renderingData);
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd); ;
        }
    }

    public void Setup(RenderTargetIdentifier currTarget)
    {
        this.currTarget = currTarget;
    }

    void Render(CommandBuffer cmd, ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;
        var source = currTarget;
        int destination = TempTargetId;

        var w = (int)(cameraData.camera.scaledPixelWidth / 1);
        var h = (int)(cameraData.camera.scaledPixelHeight / 1);

        mate.SetFloat(Shader.PropertyToID("_FogDensity"), val.FogDensity.value);
        mate.SetColor(Shader.PropertyToID("_FogColor"), val.FogColor.value);

        Matrix4x4 proj = GL.GetGPUProjectionMatrix(renderingData.cameraData.camera.projectionMatrix, false);
        mate.SetMatrix(
            Shader.PropertyToID("_InvProj"),
            proj.inverse
            );
        mate.SetMatrix(
            Shader.PropertyToID("_InvView"),
            renderingData.cameraData.camera.cameraToWorldMatrix
            );

        mate.SetVector(Shader.PropertyToID("_BoundMax"), transform.position + transform.localScale / 2);
        mate.SetVector(Shader.PropertyToID("_BoundMin"), transform.position - transform.localScale / 2);
        
        int shaderPass = 0;
        cmd.SetGlobalTexture(MainTexId, source);
        cmd.GetTemporaryRT(destination, w, h, 0, FilterMode.Point, RenderTextureFormat.Default);

        cmd.Blit(source, destination);

        cmd.GetTemporaryRT(destination, w / 2, h / 2, 0, FilterMode.Point, RenderTextureFormat.Default);
        cmd.Blit(destination, source, mate, shaderPass);
        cmd.Blit(source, destination);
    }
}

public class FogRenderFeature : ScriptableRendererFeature
{
    FogPass pass;

    public override void Create()
    {
        pass = new FogPass(RenderPassEvent.BeforeRenderingPostProcessing);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        pass.Setup(renderer.cameraColorTarget);
        renderer.EnqueuePass(pass);
    }
}
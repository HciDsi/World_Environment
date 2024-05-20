using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[Serializable]
[VolumeComponentMenuForRenderPipeline("World/Cloud", typeof(UniversalRenderPipeline))]
public class Cloud : VolumeComponent, IPostProcessComponent
{
    [Tooltip("云密度")]
    public ClampedFloatParameter CloudDensity = new ClampedFloatParameter(0.0f, 0.0f, 1.0f);

    [Tooltip("")]
    public ClampedFloatParameter LightAbsorptionTowardSun = new ClampedFloatParameter(0.1f, 0.05f, 1.0f);
    [Tooltip("")]
    public ClampedFloatParameter DarknessThreshold = new ClampedFloatParameter(0.1f, 0.05f, 1.0f);
    [Tooltip("云较亮颜色")]
    public ColorParameter CloudColor1 = new ColorParameter(new Color(224, 177, 33, 255));
    [Tooltip("云较亮颜色偏离")]
    public ClampedFloatParameter ColorOffset1 = new ClampedFloatParameter(0.1f, 0.0f, 1.0f);
    [Tooltip("云较暗颜色")]
    public ColorParameter CloudColor2 = new ColorParameter(new Color(137, 20, 20, 255));
    [Tooltip("云较暗颜色偏离")]
    public ClampedFloatParameter ColorOffset2 = new ClampedFloatParameter(0.1f, 0.0f, 1.0f);

    [Tooltip("散射混合度")]
    public Vector4Parameter PhaseParams = new Vector4Parameter(new Vector4(0.72f, 1, 0.5f, 1.58f));

    [Tooltip("云噪声纹理")]
    public Texture3DParameter CloudNoiseTex = new Texture3DParameter(null);
    [Tooltip("云噪声缩放")]
    public ClampedFloatParameter CloudNoiseTilling = new ClampedFloatParameter(0.1f, 0.1f, 1.0f);
    [Tooltip("云噪声偏移")]
    public FloatParameter CloudNoiseOffset = new FloatParameter(1);
    [Tooltip("")]
    public TextureParameter WeatherTex = new TextureParameter(null);

    public bool IsActive() => CloudDensity.value != 0.0f;
    public bool IsTileCompatible() => false;
}

public class CloudPass : ScriptableRenderPass
{
    static readonly string renderTargs = "Post Cloud Pass";
    static readonly int MainTexId = Shader.PropertyToID("_MainTex");
    static readonly int TempTargetId = Shader.PropertyToID("_TempTarget");

    Cloud val;
    Material mate;
    Transform transform;
    RenderTargetIdentifier colorTarget;

    public CloudPass(RenderPassEvent evt)
    {
        renderPassEvent = evt;

        Shader shader = Shader.Find("PostProcessing/Cloud");
        if(shader == null)
        {
            Debug.LogError("Not Find Shader " + renderTargs);
            return;
        }
        mate = CoreUtils.CreateEngineMaterial(shader);

        var box = GameObject.Find("CloudBox");
        if(box == null)
        {
            Debug.LogError("Not Create CloudBox");
            return;
        }
        transform = box.transform;
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if(mate == null)
        {
            Debug.LogError("Not Create Materil " + renderTargs);
            return;
        }
        if (transform == null)
        {
            return;
        }

        if (!renderingData.cameraData.postProcessEnabled)
            return;

        var stack = VolumeManager.instance.stack;
        val = stack.GetComponent<Cloud>();
        if (val != null && val.IsActive())
        {
            CommandBuffer cmd = CommandBufferPool.Get(renderTargs);
            Render(cmd, ref renderingData);
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    public void Setup(in RenderTargetIdentifier colorTarget)
    {
        this.colorTarget = colorTarget;
    }

    void Render(CommandBuffer cmd, ref RenderingData renderingData)
    {
        ref var cameraData = ref renderingData.cameraData;
        var source = colorTarget;
        int destination = TempTargetId;

        var w = (int)(cameraData.camera.scaledPixelWidth / 1);
        var h = (int)(cameraData.camera.scaledPixelHeight / 1);

        mate.SetFloat(Shader.PropertyToID("_Density"), val.CloudDensity.value);

        mate.SetFloat(Shader.PropertyToID("_LightAbsorptionTowardSun"), val.LightAbsorptionTowardSun.value);
        mate.SetFloat(Shader.PropertyToID("_DarknessThreshold"), val.DarknessThreshold.value);
        mate.SetColor(Shader.PropertyToID("_CloudColor1"), val.CloudColor1.value);
        mate.SetFloat(Shader.PropertyToID("_ColorOffset1"), val.ColorOffset1.value);
        mate.SetColor(Shader.PropertyToID("_CloudColor2"), val.CloudColor2.value);
        mate.SetFloat(Shader.PropertyToID("_ColorOffset2"), val.ColorOffset2.value);

        mate.SetVector(Shader.PropertyToID("_PhasePamas"), val.PhaseParams.value);

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

        Vector3 tilling = new Vector3(transform.localScale.x, transform.localScale.y, transform.localScale.z);
        mate.SetTexture(Shader.PropertyToID("_3DNoise"), val.CloudNoiseTex.value);
        mate.SetFloat(Shader.PropertyToID("_3DNoiseTilling"), val.CloudNoiseTilling.value * 10);
        mate.SetFloat(Shader.PropertyToID("_3DNoiseOffset"), val.CloudNoiseOffset.value);
        mate.SetTexture(Shader.PropertyToID("_WeatherTex"), val.WeatherTex.value);

        int shaderPass = 0;
        cmd.SetGlobalTexture(MainTexId, source);
        cmd.GetTemporaryRT(destination, w, h, 0, FilterMode.Point, RenderTextureFormat.Default);

        cmd.Blit(source, destination);

        cmd.GetTemporaryRT(destination, w / 2, h / 2, 0, FilterMode.Point, RenderTextureFormat.Default);
        cmd.Blit(destination, source, mate, shaderPass);
        cmd.Blit(source, destination);
    }

}

public class CloudRenderFeature : ScriptableRendererFeature
{
    CloudPass pass;

    public override void Create()
    {
        pass = new CloudPass(RenderPassEvent.BeforeRenderingPostProcessing);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        pass.Setup(renderer.cameraColorTarget);
        renderer.EnqueuePass(pass);
    }
}

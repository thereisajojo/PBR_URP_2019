using UnityEngine;
using UnityEditor;

public class IBL_Irradiance_Integral : EditorWindow
{
    public Cubemap cubemap;
    public int Count = 1024;//采样数
    public string path = "Textures/Irradiance Map";
    public string texName;
    private RenderTexture rt0;
    private RenderTexture rt1;
    private Material material;

    [MenuItem("Tools/IBL 辐照度预积分")]
    static void Init()
    {
        // Get existing open window or if none, make a new one:
        IBL_Irradiance_Integral window = (IBL_Irradiance_Integral)EditorWindow.GetWindowWithRect(typeof(IBL_Irradiance_Integral), new Rect(0, 0, 410, 670), false);
        window.Show();
    }

    void OnGUI()
    {
        string cubMapName;
        if(cubemap)
        {
            cubMapName = cubemap.name;
        }
        else
        {
            cubMapName = "";
        }
        cubemap = EditorGUILayout.ObjectField("CubeMap: " + cubMapName, cubemap, typeof(Cubemap), true, GUILayout.Width(400), GUILayout.Height(80)) as Cubemap;

        GUILayout.Label("Origin Texture", EditorStyles.boldLabel);
        GUILayout.Box(rt1, GUILayout.Width(400), GUILayout.Height(200));

        GUILayout.Label("Fianl Texture", EditorStyles.boldLabel);
        GUILayout.Box(rt0, GUILayout.Width(400), GUILayout.Height(200));

        path = EditorGUILayout.TextField("Save Path", path);
        texName = EditorGUILayout.TextField("OutputTex Name", texName);

        Count = EditorGUILayout.IntSlider("Sample Count", Count, 4, 2048);

        if (GUILayout.Button("Create Irradiance Random"))
        {
            Create1();
        }

        if (GUILayout.Button("Create Irradiance Riemann Sum"))
        {
            Create2();
        }

        if (GUILayout.Button("Clean"))
        {
            cubemap = null;
            rt0 = null;
            rt1 = null;
            Count = 1024;
            texName = ((int)Random.Range(0,10000)).ToString();
        }
    }

    //[Button("生成辐照度图")]
    private void Create1()
    {
        if (cubemap == null)
        {
            Debug.LogWarning("Have no cubemap");
            return;
        }
        if (texName == null || texName == "")
        {
            Debug.LogWarning("Haven't set Texture's Name");
            return;
        }
        if (material == null)
        {
            material = new Material(Shader.Find("IBLMaker_CubeMap_RandomSample"));
        }
        rt0 = new RenderTexture(cubemap.width * 2, cubemap.width, 0, RenderTextureFormat.ARGBFloat);
        rt1 = new RenderTexture(cubemap.width * 2, cubemap.width, 0, RenderTextureFormat.ARGBFloat);
        rt0.wrapMode = TextureWrapMode.Repeat;
        rt1.wrapMode = TextureWrapMode.Repeat;
        rt0.Create();
        rt1.Create();
        Graphics.Blit(cubemap, rt0, material, 0);
        material.SetTexture("_CubeTex", cubemap);
        for (int i = 0; i < Count; i++)
        {
            EditorUtility.DisplayProgressBar("", "", 1f / Count);
            Vector3 n = new Vector3(
                    Random.Range(-1f, 1f),
                    Random.Range(0.0000001f, 1f),
                    Random.Range(-1f, 1f)
                );
            while (n.magnitude > 1)//用While限制了半球内的随机取点，保证各方向的几率是一致的
                n = new Vector3(
                        Random.Range(-1f, 1f),
                        Random.Range(0.0000001f, 1f),
                        Random.Range(-1f, 1f)
                    );
            n = n.normalized;
            material.SetVector("_RandomVector", new Vector4(
                n.x, n.y, n.z,
                1f / (i + 2)
                ));
            Graphics.Blit(rt0, rt1, material, 1);
            // 翻转
            /*RenderTexture t = rt0;
            rt0 = rt1;
            rt1 = t;*/
            (rt1, rt0) = (rt0, rt1);
        }
        Graphics.Blit(cubemap, rt1, material, 0);
        EditorUtility.ClearProgressBar();
        // 保存
        Texture2D texture = new Texture2D(cubemap.width * 2, cubemap.width, TextureFormat.ARGB32, true);
        var k = RenderTexture.active;
        RenderTexture.active = rt0;
        texture.ReadPixels(new Rect(0, 0, rt0.width, rt0.height), 0, 0);
        RenderTexture.active = k;
        byte[] bytes = texture.EncodeToPNG();
        string completePath = System.IO.Path.Combine(Application.dataPath, path) + "/" + texName + "_irradiance.png";
        System.IO.FileStream fs = new System.IO.FileStream(completePath, System.IO.FileMode.Create);
        System.IO.BinaryWriter bw = new System.IO.BinaryWriter(fs);
        bw.Write(bytes);
        fs.Close();
        bw.Close();
        AssetDatabase.Refresh();
    }

    private void Create2()
    {
        if (cubemap == null)
        {
            Debug.LogWarning("Have no cubemap");
            return;
        }
        if (texName == null || texName == "")
        {
            Debug.LogWarning("Haven't set Texture's Name");
            return;
        }
        if (material == null)
        {
            material = new Material(Shader.Find("IBLMaker_CubeMap_RandomSample"));
        }
        rt0 = new RenderTexture(cubemap.width * 2, cubemap.width, 0, RenderTextureFormat.ARGBFloat);
        rt1 = new RenderTexture(cubemap.width * 2, cubemap.width, 0, RenderTextureFormat.ARGBFloat);
        rt0.wrapMode = TextureWrapMode.Repeat;
        rt1.wrapMode = TextureWrapMode.Repeat;
        rt0.Create();
        rt1.Create();
        Graphics.Blit(cubemap, rt1, material, 0);
        material.SetTexture("_CubeTex", cubemap);

        Graphics.Blit(rt1, rt0);

        float sampleDelta = Mathf.PI / (Mathf.Sqrt(Count));//采样角间隔
        material.SetFloat("_SampleDelta", sampleDelta);
        Graphics.Blit(rt0, material, 2);

        EditorUtility.ClearProgressBar();
        // 保存
        Texture2D texture = new Texture2D(cubemap.width * 2, cubemap.width, TextureFormat.ARGB32, true);
        var k = RenderTexture.active;
        RenderTexture.active = rt0;
        texture.ReadPixels(new Rect(0, 0, rt0.width, rt0.height), 0, 0);
        RenderTexture.active = k;
        byte[] bytes = texture.EncodeToPNG();
        string completePath = System.IO.Path.Combine(Application.dataPath, path) + "/" + texName + "_irradiance.png";
        System.IO.FileStream fs = new System.IO.FileStream(completePath, System.IO.FileMode.Create);
        System.IO.BinaryWriter bw = new System.IO.BinaryWriter(fs);
        bw.Write(bytes);
        fs.Close();
        bw.Close();
        AssetDatabase.Refresh();
    }
}
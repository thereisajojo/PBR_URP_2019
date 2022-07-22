using System.IO;
using UnityEditor;
using UnityEngine;

public class Create_BRDF_LUT
{
    [MenuItem("Tools/Create BRDF_LUT")]
    static void CreateBrdfLut()
    {
        const int texSize = 1024;

        RenderTexture lutRT = new RenderTexture(texSize, texSize, 0, RenderTextureFormat.RG16, RenderTextureReadWrite.Linear);

        Shader shader = Shader.Find("BRDF_LUT_IBL");
        if(shader == null)
        {
            Debug.LogWarning("dont find shader");
            return;
        }
        Material material = new Material(shader);

        RenderTexture active = RenderTexture.active;
        RenderTexture.active = lutRT;

        Graphics.Blit(lutRT, material, 0);

        Texture2D lutPNG = new Texture2D(texSize, texSize, TextureFormat.RGBA32, false, true);
        lutPNG.ReadPixels(new Rect(0, 0, lutRT.width, lutRT.height), 0, 0);
        lutPNG.Apply();
        byte[] bytes = lutPNG.EncodeToPNG();

        RenderTexture.active = active;

        string savePath = "Assets/Textures/LUT/ibl_brdf_lut_" + texSize.ToString() + ".png";
        FileStream fs = File.Open(savePath, FileMode.Create);
        if(fs == null)
        {
            Debug.LogWarning("没有找到路径");
            return;
        }
        Debug.Log("创建路径" + fs.Name);
        BinaryWriter write = new BinaryWriter(fs);
        write.Write(bytes);
        write.Flush();
        fs.Close();
        write.Close();

        AssetDatabase.Refresh();
        Debug.Log("创建成功");
    }
}

// Headless shot render for tools/render-shot.py (engine "unity", R55-R57). Copy this folder's Editor/ into the Unity
// project's Assets/ and install the Recorder package (com.unity.recorder). render-shot runs:
//   Unity.exe -batchmode -projectPath <project> -executeMethod AosRender.RenderShot -logFile - -aosScene <scene>
//     -aosShot <variant> -aosFrames <n> -aosSize <w>x<h> -aosFps <fps> -aosOut <frames folder>
// It opens the scene, enters play mode without a domain reload, records frames 0..n-1 as PNG at a constant capture
// rate (game time follows the capture clock, not the wall clock) and exits. The variant reaches shot scripts as the
// AOS_SHOT environment variable; the film's look is engines/look.json.
// UNVERIFIED: written before Unity was installed on this machine; the first Unity spike must run it and fix it.
using System;
using System.IO;
using UnityEditor;
using UnityEditor.Recorder;
using UnityEditor.Recorder.Input;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class AosRender
{
    static RecorderController controller;
    static bool started;

    static string Arg(string name)
    {
        var args = Environment.GetCommandLineArgs();
        int i = Array.IndexOf(args, name);
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }

    public static void RenderShot()
    {
        int frames = int.Parse(Arg("-aosFrames"));
        int fps = int.Parse(Arg("-aosFps"));
        string[] size = Arg("-aosSize").Split('x');
        string outDir = Arg("-aosOut");
        Environment.SetEnvironmentVariable("AOS_SHOT", Arg("-aosShot") ?? "");
        Directory.CreateDirectory(outDir);
        EditorSceneManager.OpenScene(Arg("-aosScene"));

        var image = ScriptableObject.CreateInstance<ImageRecorderSettings>();
        image.name = "aos";
        image.Enabled = true;
        image.OutputFormat = ImageRecorderSettings.ImageRecorderOutputFormat.PNG;
        image.imageInputSettings = new GameViewInputSettings { OutputWidth = int.Parse(size[0]), OutputHeight = int.Parse(size[1]) };
        image.OutputFile = Path.Combine(outDir, "f_") + DefaultWildcard.Frame;

        var settings = ScriptableObject.CreateInstance<RecorderControllerSettings>();
        settings.AddRecorderSettings(image);
        settings.SetRecordModeToFrameInterval(0, frames - 1);
        settings.FrameRatePlayback = FrameRatePlayback.Constant;
        settings.FrameRate = fps;
        settings.CapFrameRate = false;
        controller = new RecorderController(settings);

        // keep static state across entering play mode
        EditorSettings.enterPlayModeOptionsEnabled = true;
        EditorSettings.enterPlayModeOptions = EnterPlayModeOptions.DisableDomainReload;
        EditorApplication.update += Tick;
        EditorApplication.isPlaying = true;
    }

    static void Tick()
    {
        if (!EditorApplication.isPlaying)
            return;
        if (!started)
        {
            controller.PrepareRecording();
            controller.StartRecording();
            started = true;
            return;
        }
        if (!controller.IsRecording())
        {
            EditorApplication.update -= Tick;
            EditorApplication.Exit(0);
        }
    }
}

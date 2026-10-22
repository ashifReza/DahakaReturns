using UnrealBuildTool;

public class RelentlessEditorTarget : TargetRules
{
	public RelentlessEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("Relentless");
	}
}

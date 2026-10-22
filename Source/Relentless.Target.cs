using UnrealBuildTool;

public class RelentlessTarget : TargetRules
{
	public RelentlessTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("Relentless");
	}
}

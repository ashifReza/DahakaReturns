#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "RelentlessHUD.generated.h"

// Deliberately minimal: a dot, stamina only when it matters, battery, prompts.
UCLASS()
class RELENTLESS_API ARelentlessHUD : public AHUD
{
	GENERATED_BODY()

public:
	virtual void DrawHUD() override;

private:
	void DrawCenteredText(const FString& Text, float CenterX, float Y, const FLinearColor& Color, float Scale = 1.f);
	void DrawBar(float X, float Y, float W, float H, float Fill, const FLinearColor& Color);
};

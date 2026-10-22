#include "RelentlessHUD.h"
#include "RelentlessCharacter.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Engine/Font.h"

void ARelentlessHUD::DrawHUD()
{
	Super::DrawHUD();

	const ARelentlessCharacter* Player = Cast<ARelentlessCharacter>(GetOwningPawn());
	if (!Player || !Canvas)
	{
		return;
	}
	const float W = Canvas->ClipX;
	const float H = Canvas->ClipY;
	const float UIScale = H / 1080.f;

	if (!Player->IsDead())
	{
		DrawRect(FLinearColor(1.f, 1.f, 1.f, 0.25f), W * 0.5f - 1.5f, H * 0.5f - 1.5f, 3.f, 3.f);

		const float Stamina = Player->GetStamina01();
		if (Stamina < 0.999f)
		{
			const FLinearColor Color = Player->IsExhausted() ? FLinearColor(0.7f, 0.1f, 0.08f, 0.8f) : FLinearColor(0.85f, 0.85f, 0.8f, 0.5f);
			DrawBar(W * 0.5f - 130.f * UIScale, H - 70.f * UIScale, 260.f * UIScale, 4.f * UIScale, Stamina, Color);
		}

		const float Battery = Player->GetBattery01();
		const FLinearColor BatteryColor = Battery < 0.2f ? FLinearColor(0.8f, 0.2f, 0.1f, 0.8f) : FLinearColor(0.6f, 0.8f, 0.6f, 0.5f);
		DrawBar(W - 150.f * UIScale, H - 60.f * UIScale, 100.f * UIScale, 10.f * UIScale, Battery, BatteryColor);

		const FText Prompt = Player->GetInteractPrompt();
		if (!Prompt.IsEmpty())
		{
			DrawCenteredText(Prompt.ToString(), W * 0.5f, H * 0.5f + 40.f * UIScale, FLinearColor(0.9f, 0.9f, 0.85f, 0.9f), UIScale);
			const float Progress = Player->GetInteractProgress();
			if (Progress >= 0.f)
			{
				DrawBar(W * 0.5f - 80.f * UIScale, H * 0.5f + 75.f * UIScale, 160.f * UIScale, 5.f * UIScale, Progress, FLinearColor(0.9f, 0.9f, 0.85f, 0.9f));
			}
		}
	}

	const float HintAlpha = Player->GetHintAlpha();
	if (HintAlpha > 0.f && !Player->GetHintText().IsEmpty())
	{
		DrawCenteredText(Player->GetHintText().ToString(), W * 0.5f, H * 0.78f, FLinearColor(0.85f, 0.85f, 0.8f, HintAlpha), UIScale * 1.1f);
	}
}

void ARelentlessHUD::DrawCenteredText(const FString& Text, float CenterX, float Y, const FLinearColor& Color, float Scale)
{
	UFont* Font = GEngine ? GEngine->GetMediumFont() : nullptr;
	float TextW = 0.f;
	float TextH = 0.f;
	GetTextSize(Text, TextW, TextH, Font, Scale);
	DrawText(Text, Color, CenterX - TextW * 0.5f, Y, Font, Scale);
}

void ARelentlessHUD::DrawBar(float X, float Y, float W, float H, float Fill, const FLinearColor& Color)
{
	DrawRect(FLinearColor(0.f, 0.f, 0.f, 0.4f), X, Y, W, H);
	DrawRect(Color, X, Y, W * FMath::Clamp(Fill, 0.f, 1.f), H);
}

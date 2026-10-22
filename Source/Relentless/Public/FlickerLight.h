#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "FlickerLight.generated.h"

class UPointLightComponent;

// A failing ceiling light. Sputters on its own, and dies outright when the
// pursuer passes beneath it, so you can watch it coming down a corridor.
UCLASS()
class RELENTLESS_API AFlickerLight : public AActor
{
	GENERATED_BODY()

public:
	AFlickerLight();
	virtual void OnConstruction(const FTransform& Transform) override;
	virtual void Tick(float DeltaTime) override;

	UPROPERTY(EditAnywhere, Category = "Light")
	float Lumens = 60.f;

	UPROPERTY(EditAnywhere, Category = "Light")
	FLinearColor LightColor = FLinearColor(0.85f, 0.95f, 1.f);

	UPROPERTY(EditAnywhere, Category = "Light")
	float Radius = 900.f;

	// 0 = steady, 1 = barely working.
	UPROPERTY(EditAnywhere, Category = "Light", meta = (ClampMin = 0, ClampMax = 1))
	float Faultiness = 0.3f;

	// The light dies while the pursuer is within this distance.
	UPROPERTY(EditAnywhere, Category = "Light")
	float DarkenRadius = 700.f;

protected:
	virtual void BeginPlay() override;

	UPROPERTY(VisibleAnywhere, Category = "Light")
	TObjectPtr<UPointLightComponent> Light;

	UPROPERTY(VisibleAnywhere, Category = "Light")
	TObjectPtr<UStaticMeshComponent> Fixture;

private:
	void ApplySettings();

	float Seed = 0.f;
	float Level = 1.f;
};

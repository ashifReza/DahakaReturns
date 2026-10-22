#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "BatteryPickup.generated.h"

class USphereComponent;
class UPointLightComponent;
class USoundBase;

// Placed just off the escape route: worth the detour, if you dare.
UCLASS()
class RELENTLESS_API ABatteryPickup : public AActor
{
	GENERATED_BODY()

public:
	ABatteryPickup();
	virtual void Tick(float DeltaTime) override;

	UPROPERTY(EditAnywhere, Category = "Battery")
	float Amount = 40.f;

	UPROPERTY(EditAnywhere, Category = "Battery")
	TObjectPtr<USoundBase> PickupSound;

protected:
	virtual void BeginPlay() override;

	UPROPERTY(VisibleAnywhere, Category = "Battery")
	TObjectPtr<USphereComponent> Sphere;

	UPROPERTY(VisibleAnywhere, Category = "Battery")
	TObjectPtr<UStaticMeshComponent> Mesh;

	UPROPERTY(VisibleAnywhere, Category = "Battery")
	TObjectPtr<UPointLightComponent> Glow;

	UFUNCTION()
	void OnOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor, UPrimitiveComponent* OtherComp, int32 OtherBodyIndex, bool bFromSweep, const FHitResult& SweepResult);
};

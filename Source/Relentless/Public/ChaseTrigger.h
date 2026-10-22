#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ChaseTrigger.generated.h"

class UBoxComponent;
class USoundBase;

// Walk into it once. With bStartsChase it begins the chase, or, if one is
// already running, becomes the new checkpoint. Without it, it just shows a hint.
UCLASS()
class RELENTLESS_API AChaseTrigger : public AActor
{
	GENERATED_BODY()

public:
	AChaseTrigger();

	FTransform GetPlayerRespawnWorld() const { return PlayerRespawn * GetActorTransform(); }
	FTransform GetPursuerStartWorld() const { return PursuerStart * GetActorTransform(); }

	UPROPERTY(EditAnywhere, Category = "Chase")
	bool bStartsChase = true;

	// Where the pursuer appears (relative to this trigger). Drag the widget in the viewport.
	UPROPERTY(EditAnywhere, Category = "Chase", meta = (MakeEditWidget = true, EditCondition = "bStartsChase"))
	FTransform PursuerStart = FTransform(FVector(-1200.f, 0.f, 0.f));

	// Where the player comes back after dying past this point.
	UPROPERTY(EditAnywhere, Category = "Chase", meta = (MakeEditWidget = true, EditCondition = "bStartsChase"))
	FTransform PlayerRespawn = FTransform(FVector(100.f, 0.f, 0.f));

	UPROPERTY(EditAnywhere, Category = "Chase", meta = (EditCondition = "bStartsChase"))
	float ActivationDelay = 0.4f;

	UPROPERTY(EditAnywhere, Category = "Chase")
	FText Hint;

	UPROPERTY(EditAnywhere, Category = "Chase")
	float HintDuration = 4.f;

	UPROPERTY(EditAnywhere, Category = "Chase")
	TObjectPtr<USoundBase> Stinger;

protected:
	UPROPERTY(VisibleAnywhere, Category = "Chase")
	TObjectPtr<UBoxComponent> Box;

	UFUNCTION()
	void OnOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor, UPrimitiveComponent* OtherComp, int32 OtherBodyIndex, bool bFromSweep, const FHitResult& SweepResult);

private:
	bool bTriggered = false;
};

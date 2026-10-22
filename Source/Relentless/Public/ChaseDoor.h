#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ChaseInteractable.h"
#include "ChaseDoor.generated.h"

class USoundBase;

UENUM(BlueprintType)
enum class EChaseDoorState : uint8
{
	Open,
	Closed,
	Broken
};

// A door you can slam in its face (it bashes through after a few seconds), or a
// heavy door you must hold E to force open while you hear it coming.
UCLASS()
class RELENTLESS_API AChaseDoor : public AActor, public IChaseInteractable
{
	GENERATED_BODY()

public:
	AChaseDoor();

	virtual void OnConstruction(const FTransform& Transform) override;
	virtual void Tick(float DeltaTime) override;

	// IChaseInteractable
	virtual bool CanInteract() const override;
	virtual FText GetInteractPrompt() const override;
	virtual void BeginInteract(ARelentlessCharacter* By) override;
	virtual void EndInteract(ARelentlessCharacter* By) override;
	virtual float GetInteractProgress() const override;

	bool IsBlocking() const;
	void Rattle();
	void Smash(const FVector& Direction);

protected:
	virtual void BeginPlay() override;

	UPROPERTY(VisibleAnywhere, Category = "Door")
	TObjectPtr<USceneComponent> Root;

	UPROPERTY(VisibleAnywhere, Category = "Door")
	TObjectPtr<USceneComponent> Hinge;

	UPROPERTY(VisibleAnywhere, Category = "Door")
	TObjectPtr<UStaticMeshComponent> Panel;

	UPROPERTY(EditAnywhere, Category = "Door")
	float Width = 200.f;

	UPROPERTY(EditAnywhere, Category = "Door")
	float Height = 290.f;

	UPROPERTY(EditAnywhere, Category = "Door")
	float Thickness = 10.f;

	// Positive swings toward +Y of the door actor.
	UPROPERTY(EditAnywhere, Category = "Door")
	float OpenYaw = 90.f;

	UPROPERTY(EditAnywhere, Category = "Door")
	bool bStartsOpen = true;

	// Heavy doors start shut, must be held open, and can't be slammed again.
	UPROPERTY(EditAnywhere, Category = "Door")
	bool bHeavy = false;

	UPROPERTY(EditAnywhere, Category = "Door", meta = (EditCondition = "bHeavy"))
	float HoldTime = 1.6f;

	UPROPERTY(EditAnywhere, Category = "Door")
	FLinearColor Color = FLinearColor(0.16f, 0.09f, 0.05f);

	UPROPERTY(EditAnywhere, Category = "Sounds")
	TObjectPtr<USoundBase> SlamSound;

	UPROPERTY(EditAnywhere, Category = "Sounds")
	TObjectPtr<USoundBase> CreakSound;

	UPROPERTY(EditAnywhere, Category = "Sounds")
	TObjectPtr<USoundBase> BreakSound;

private:
	void LayoutPanel();
	void SetDoorState(EChaseDoorState NewState, float Speed);
	void ResetDoor();

	EChaseDoorState State = EChaseDoorState::Open;
	float CurrentYaw = 0.f;
	float TargetYaw = 0.f;
	float SwingSpeed = 4.f;
	float RattleTime = 0.f;
	float HoldProgress = 0.f;
	TWeakObjectPtr<ARelentlessCharacter> Holder;
};

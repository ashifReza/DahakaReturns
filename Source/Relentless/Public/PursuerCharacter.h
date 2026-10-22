#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "PursuerCharacter.generated.h"

class ARelentlessCharacter;
class AChaseDoor;
class UPointLightComponent;
class USoundBase;

UENUM(BlueprintType)
enum class EPursuerState : uint8
{
	Dormant,	// Hidden, waiting for a chase trigger.
	Chasing,
	Bashing,	// Smashing through a door.
	Stunned,	// Caught in the focused flashlight beam.
	Lost,		// Player slipped into a crawlspace.
	Retreating,	// Player reached a safe zone.
	Feeding		// Caught the player.
};

// The thing behind you. It doesn't path-find: it follows the exact trail of
// breadcrumbs you leave, so it always comes the way you came. Its speed is
// rubber-banded to stay just behind you; only mistakes get you killed.
UCLASS()
class RELENTLESS_API APursuerCharacter : public ACharacter
{
	GENERATED_BODY()

public:
	APursuerCharacter();

	virtual void Tick(float DeltaTime) override;

	void Activate();
	void ResetTo(const FTransform& Where);
	void TryStun();
	void LosePlayer();
	void Reappear(const FTransform& Where);
	void ResumeChase();
	void Retreat();

	EPursuerState GetState() const { return State; }
	bool IsActiveThreat() const;
	float GetTrailGap() const { return TrailGap; }
	FVector GetHeadLocation() const;

protected:
	virtual void BeginPlay() override;

	// --- Chase tuning (speeds are multiples of the player's sprint speed) ---

	// Gap it tries to hold. At or below this it runs at NearSpeedScale.
	UPROPERTY(EditAnywhere, Category = "Chase")
	float IdealGap = 650.f;

	// At or beyond this gap it runs at FarSpeedScale to catch back up.
	UPROPERTY(EditAnywhere, Category = "Chase")
	float FarGap = 1600.f;

	// Just under sprint speed: a sprinting player slowly escapes, anyone else doesn't.
	UPROPERTY(EditAnywhere, Category = "Chase")
	float NearSpeedScale = 0.9f;

	UPROPERTY(EditAnywhere, Category = "Chase")
	float FarSpeedScale = 1.35f;

	// Hidden mercy: eases off a little when the player is out of breath.
	UPROPERTY(EditAnywhere, Category = "Chase")
	float ExhaustionMercy = 0.85f;

	UPROPERTY(EditAnywhere, Category = "Chase")
	float KillDistance = 180.f;

	UPROPERTY(EditAnywhere, Category = "Chase")
	float CrumbSpacing = 60.f;

	UPROPERTY(EditAnywhere, Category = "Chase")
	float BashTime = 2.5f;

	UPROPERTY(EditAnywhere, Category = "Chase")
	float StunDuration = 1.3f;

	UPROPERTY(EditAnywhere, Category = "Chase")
	float StunCooldown = 3.5f;

	// How long it lingers at a crawlspace before vanishing to go round.
	UPROPERTY(EditAnywhere, Category = "Chase")
	float LostConcealDelay = 2.5f;

	// --- Sounds (all optional) ---

	UPROPERTY(EditAnywhere, Category = "Sounds")
	TObjectPtr<USoundBase> RoarSound;

	UPROPERTY(EditAnywhere, Category = "Sounds")
	TObjectPtr<USoundBase> FootstepSound;

	UPROPERTY(EditAnywhere, Category = "Sounds")
	TObjectPtr<USoundBase> BashSound;

	UPROPERTY(EditAnywhere, Category = "Sounds")
	TObjectPtr<USoundBase> ScreechSound;

	UPROPERTY(EditAnywhere, Category = "Sounds")
	float FootstepStride = 190.f;

	// --- Greybox body ---

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<USceneComponent> BodyRoot;

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<UStaticMeshComponent> Torso;

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<UStaticMeshComponent> Head;

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<UStaticMeshComponent> HornLeft;

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<UStaticMeshComponent> HornRight;

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<USceneComponent> ShoulderLeft;

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<USceneComponent> ShoulderRight;

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<UStaticMeshComponent> ArmLeft;

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<UStaticMeshComponent> ArmRight;

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<UStaticMeshComponent> LegLeft;

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<UStaticMeshComponent> LegRight;

	UPROPERTY(VisibleAnywhere, Category = "Body")
	TObjectPtr<UPointLightComponent> EyeGlow;

private:
	void EnterState(EPursuerState NewState);
	void SetConcealed(bool bConceal);
	void ResetTrail();
	void RecordTrail(const ARelentlessCharacter* Player);
	void UpdateGap(const ARelentlessCharacter* Player);
	void UpdateSpeed(const ARelentlessCharacter* Player);
	bool CheckCatch(ARelentlessCharacter* Player);
	bool CheckDoors();
	void FollowTrail(const ARelentlessCharacter* Player, float DeltaTime);
	void Animate(float DeltaTime);
	void PlaySound(USoundBase* Sound, float Volume = 1.f);
	FVector GetFeetLocation() const;
	ARelentlessCharacter* GetPlayer() const;

	EPursuerState State = EPursuerState::Dormant;
	float StateTime = 0.f;
	float StunCooldownLeft = 0.f;
	float StuckTime = 0.f;
	float NextBashHit = 0.f;
	float AnimPhase = 0.f;
	float StepDistance = 0.f;
	float TrailGap = UE_BIG_NUMBER;
	bool bConcealed = false;

	TArray<FVector> Trail;
	int32 TrailIndex = 0;
	TWeakObjectPtr<AChaseDoor> BashTarget;
};

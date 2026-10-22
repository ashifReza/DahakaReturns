#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "RelentlessCharacter.generated.h"

class UCameraComponent;
class USpotLightComponent;
class UStaticMeshComponent;
class UInputAction;
class UInputMappingContext;
class APursuerCharacter;
class USoundBase;
struct FInputActionValue;

// First-person survivor: flashlight, stamina, and the look-back.
UCLASS()
class RELENTLESS_API ARelentlessCharacter : public ACharacter
{
	GENERATED_BODY()

public:
	ARelentlessCharacter();

	virtual void Tick(float DeltaTime) override;
	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;

	// The pursuer reached us.
	void Caught(APursuerCharacter* Killer);
	void Respawn(const FTransform& Where);

	void AddBattery(float Amount);
	void SetForcedCrouch(bool bForce);
	void ShowHint(const FText& Text, float Duration = 4.f);

	float GetSprintSpeed() const { return SprintSpeed; }
	bool IsExhausted() const { return bExhausted; }
	bool IsDead() const { return bDead; }
	float GetStamina01() const { return Stamina / MaxStamina; }
	float GetBattery01() const { return Battery / MaxBattery; }
	bool IsFlashlightOn() const { return bFlashlightOn; }
	FVector GetFeetLocation() const;
	FVector GetEyeLocation() const;

	FText GetInteractPrompt() const;
	float GetInteractProgress() const;
	const FText& GetHintText() const { return HintText; }
	float GetHintAlpha() const;

protected:
	virtual void BeginPlay() override;

	UPROPERTY(VisibleAnywhere, Category = "Components")
	TObjectPtr<UCameraComponent> Camera;

	UPROPERTY(VisibleAnywhere, Category = "Components")
	TObjectPtr<USpotLightComponent> Flashlight;

	UPROPERTY(VisibleAnywhere, Category = "Components")
	TObjectPtr<UStaticMeshComponent> FlashlightMesh;

	UPROPERTY(EditAnywhere, Category = "Movement")
	float WalkSpeed = 300.f;

	UPROPERTY(EditAnywhere, Category = "Movement")
	float SprintSpeed = 620.f;

	// Speed while holding sprint with no stamina left.
	UPROPERTY(EditAnywhere, Category = "Movement")
	float ExhaustedSpeed = 400.f;

	UPROPERTY(EditAnywhere, Category = "Movement")
	float CrouchSpeed = 180.f;

	// Running while looking over your shoulder costs you.
	UPROPERTY(EditAnywhere, Category = "Movement")
	float LookBackSpeedScale = 0.85f;

	UPROPERTY(EditAnywhere, Category = "Stamina")
	float MaxStamina = 100.f;

	UPROPERTY(EditAnywhere, Category = "Stamina")
	float SprintDrain = 10.f;

	// Gentler drain while actually being chased, so chases are about routes, not meters.
	UPROPERTY(EditAnywhere, Category = "Stamina")
	float ChaseSprintDrain = 4.f;

	UPROPERTY(EditAnywhere, Category = "Stamina")
	float StaminaRegen = 15.f;

	UPROPERTY(EditAnywhere, Category = "Stamina")
	float ExhaustedRecoverAt = 30.f;

	UPROPERTY(EditAnywhere, Category = "Flashlight")
	float MaxBattery = 100.f;

	UPROPERTY(EditAnywhere, Category = "Flashlight")
	float BatteryDrain = 0.4f;

	// Focusing the beam (right mouse) stuns the pursuer but eats the battery.
	UPROPERTY(EditAnywhere, Category = "Flashlight")
	float FocusDrain = 7.f;

	UPROPERTY(EditAnywhere, Category = "Flashlight")
	float FlashlightLumens = 400.f;

	UPROPERTY(EditAnywhere, Category = "Flashlight")
	float FocusMultiplier = 2.2f;

	UPROPERTY(EditAnywhere, Category = "Flashlight")
	float OuterCone = 28.f;

	UPROPERTY(EditAnywhere, Category = "Flashlight")
	float FocusOuterCone = 13.f;

	UPROPERTY(EditAnywhere, Category = "Flashlight")
	float StunRange = 1500.f;

	UPROPERTY(EditAnywhere, Category = "Camera")
	float BaseFOV = 90.f;

	UPROPERTY(EditAnywhere, Category = "Camera")
	float SprintFOVBoost = 8.f;

	UPROPERTY(EditAnywhere, Category = "Camera")
	float LookBackYaw = 170.f;

	UPROPERTY(EditAnywhere, Category = "Camera")
	float LookBackBlendSpeed = 7.f;

	UPROPERTY(EditAnywhere, Category = "Camera")
	float StandingEyeHeight = 165.f;

	UPROPERTY(EditAnywhere, Category = "Camera")
	float CrouchedEyeHeight = 75.f;

	// Fixed exposure (EV100). Lower = brighter world. Horror lives around 2-4.
	UPROPERTY(EditAnywhere, Category = "Camera")
	float ExposureEV = 3.f;

	UPROPERTY(EditAnywhere, Category = "Interaction")
	float InteractRange = 230.f;

	UPROPERTY(EditAnywhere, Category = "Sounds")
	TObjectPtr<USoundBase> FlashlightClickSound;

	UPROPERTY(EditAnywhere, Category = "Sounds")
	TObjectPtr<USoundBase> DeathSound;

private:
	void BuildInput(class UEnhancedInputComponent* Input);

	void Move(const FInputActionValue& Value);
	void StopMove(const FInputActionValue& Value);
	void Look(const FInputActionValue& Value);
	void SprintPressed() { bSprintHeld = true; }
	void SprintReleased() { bSprintHeld = false; }
	void CrouchPressed();
	void CrouchReleased();
	void JumpPressed();
	void LookBackPressed() { bLookBackHeld = true; }
	void LookBackReleased() { bLookBackHeld = false; }
	void ToggleFlashlight();
	void FocusPressed() { bFocusHeld = true; }
	void FocusReleased() { bFocusHeld = false; }
	void InteractPressed();
	void InteractReleased();

	void UpdateMovement(float DeltaTime);
	void UpdateFlashlight(float DeltaTime);
	void UpdateCamera(float DeltaTime);
	void UpdateInteractTarget();
	void TryStunPursuer();
	float GetDanger() const;

	UPROPERTY(Transient)
	TObjectPtr<UInputMappingContext> MappingContext;

	UPROPERTY(Transient)
	TArray<TObjectPtr<UInputAction>> Actions;

	FVector2D MoveInput = FVector2D::ZeroVector;
	bool bSprintHeld = false;
	bool bCrouchHeld = false;
	bool bForcedCrouch = false;
	bool bLookBackHeld = false;
	bool bFocusHeld = false;
	bool bSprinting = false;
	bool bExhausted = false;
	bool bFlashlightOn = true;
	bool bDead = false;

	float Stamina = 100.f;
	float Battery = 100.f;
	float LookBackAlpha = 0.f;
	float BobPhase = 0.f;
	float EyeHeight = 165.f;
	FRotator LastViewRotation = FRotator::ZeroRotator;

	TWeakObjectPtr<APursuerCharacter> KilledBy;
	TWeakObjectPtr<AActor> FocusedActor;
	TWeakObjectPtr<AActor> InteractingActor;

	FText HintText;
	float HintEndTime = -1.f;
	float HintDuration = 1.f;
};

#include "RelentlessCharacter.h"
#include "ChaseInteractable.h"
#include "ChaseSubsystem.h"
#include "GreyboxUtils.h"
#include "PursuerCharacter.h"
#include "Camera/CameraComponent.h"
#include "Camera/PlayerCameraManager.h"
#include "Components/CapsuleComponent.h"
#include "Components/SpotLightComponent.h"
#include "Components/StaticMeshComponent.h"
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "Engine/LocalPlayer.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "InputAction.h"
#include "InputMappingContext.h"
#include "InputModifiers.h"
#include "Kismet/GameplayStatics.h"
#include "TimerManager.h"
#include "UObject/ConstructorHelpers.h"

ARelentlessCharacter::ARelentlessCharacter()
{
	PrimaryActorTick.bCanEverTick = true;

	GetCapsuleComponent()->InitCapsuleSize(34.f, 90.f);
	bUseControllerRotationYaw = true;
	bUseControllerRotationPitch = false;
	bUseControllerRotationRoll = false;

	UCharacterMovementComponent* Move = GetCharacterMovement();
	Move->MaxWalkSpeed = WalkSpeed;
	Move->MaxWalkSpeedCrouched = CrouchSpeed;
	Move->GetNavAgentPropertiesRef().bCanCrouch = true;
	Move->SetCrouchedHalfHeight(44.f);
	Move->BrakingDecelerationWalking = 1600.f;
	Move->GroundFriction = 8.f;
	Move->JumpZVelocity = 420.f;
	Move->AirControl = 0.3f;

	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(GetCapsuleComponent());
	Camera->SetRelativeLocation(FVector(0.f, 0.f, StandingEyeHeight - 90.f));
	// We drive the camera rotation ourselves so it can turn around independently of movement.
	Camera->bUsePawnControlRotation = false;
	Camera->SetFieldOfView(BaseFOV);

	// Offset from the eye so shadows have parallax: things move in the dark as you turn.
	Flashlight = CreateDefaultSubobject<USpotLightComponent>(TEXT("Flashlight"));
	Flashlight->SetupAttachment(Camera);
	Flashlight->SetRelativeLocation(FVector(25.f, 16.f, -14.f));
	Flashlight->IntensityUnits = ELightUnits::Lumens;
	Flashlight->Intensity = FlashlightLumens;
	Flashlight->OuterConeAngle = OuterCone;
	Flashlight->InnerConeAngle = 12.f;
	Flashlight->AttenuationRadius = 2600.f;
	Flashlight->SetCastShadows(true);
	Flashlight->SetVolumetricScatteringIntensity(1.5f);
	Flashlight->LightColor = FColor(255, 241, 220);

	static ConstructorHelpers::FObjectFinder<UStaticMesh> CylinderMesh(Greybox::CylinderPath);
	FlashlightMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("FlashlightMesh"));
	FlashlightMesh->SetupAttachment(Camera);
	FlashlightMesh->SetStaticMesh(CylinderMesh.Object);
	FlashlightMesh->SetRelativeLocation(FVector(32.f, 18.f, -20.f));
	FlashlightMesh->SetRelativeRotation(FRotator(-90.f, 0.f, 0.f));
	FlashlightMesh->SetRelativeScale3D(FVector(0.045f, 0.045f, 0.2f));
	FlashlightMesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	FlashlightMesh->SetCastShadow(false);

	FPostProcessSettings& PP = Camera->PostProcessSettings;
	PP.bOverride_AutoExposureMinBrightness = true;
	PP.bOverride_AutoExposureMaxBrightness = true;
	PP.bOverride_VignetteIntensity = true;
	PP.bOverride_FilmGrainIntensity = true;
	PP.bOverride_SceneFringeIntensity = true;
	PP.bOverride_ColorSaturation = true;
	PP.bOverride_MotionBlurAmount = true;
	PP.MotionBlurAmount = 0.35f;
}

void ARelentlessCharacter::BeginPlay()
{
	Super::BeginPlay();

	Stamina = MaxStamina;
	Battery = MaxBattery;
	EyeHeight = StandingEyeHeight;
	Camera->PostProcessSettings.AutoExposureMinBrightness = ExposureEV;
	Camera->PostProcessSettings.AutoExposureMaxBrightness = ExposureEV;
	Greybox::Tint(FlashlightMesh, FLinearColor(0.02f, 0.02f, 0.02f));

	if (UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>())
	{
		Chase->RegisterPlayer(this);
	}
	if (Controller)
	{
		LastViewRotation = Controller->GetControlRotation();
	}
}

// ---------------------------------------------------------------------------
// Input. Built in code so the project needs no input assets to run.
// ---------------------------------------------------------------------------

void ARelentlessCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);

	if (UEnhancedInputComponent* Input = Cast<UEnhancedInputComponent>(PlayerInputComponent))
	{
		BuildInput(Input);
	}
}

void ARelentlessCharacter::BuildInput(UEnhancedInputComponent* Input)
{
	MappingContext = NewObject<UInputMappingContext>(this);
	Actions.Reset();

	auto MakeAction = [this](EInputActionValueType Type)
	{
		UInputAction* Action = NewObject<UInputAction>(this);
		Action->ValueType = Type;
		Actions.Add(Action);
		return Action;
	};

	UInputAction* MoveAction = MakeAction(EInputActionValueType::Axis2D);
	{
		// W/S drive Y, A/D drive X.
		FEnhancedActionKeyMapping& W = MappingContext->MapKey(MoveAction, EKeys::W);
		W.Modifiers.Add(NewObject<UInputModifierSwizzleAxis>(MappingContext));
		FEnhancedActionKeyMapping& S = MappingContext->MapKey(MoveAction, EKeys::S);
		S.Modifiers.Add(NewObject<UInputModifierSwizzleAxis>(MappingContext));
		S.Modifiers.Add(NewObject<UInputModifierNegate>(MappingContext));
		FEnhancedActionKeyMapping& A = MappingContext->MapKey(MoveAction, EKeys::A);
		A.Modifiers.Add(NewObject<UInputModifierNegate>(MappingContext));
		MappingContext->MapKey(MoveAction, EKeys::D);
	}
	UInputAction* LookAction = MakeAction(EInputActionValueType::Axis2D);
	MappingContext->MapKey(LookAction, EKeys::Mouse2D);

	UInputAction* SprintAction = MakeAction(EInputActionValueType::Boolean);
	MappingContext->MapKey(SprintAction, EKeys::LeftShift);
	UInputAction* CrouchAction = MakeAction(EInputActionValueType::Boolean);
	MappingContext->MapKey(CrouchAction, EKeys::LeftControl);
	MappingContext->MapKey(CrouchAction, EKeys::C);
	UInputAction* JumpAction = MakeAction(EInputActionValueType::Boolean);
	MappingContext->MapKey(JumpAction, EKeys::SpaceBar);
	UInputAction* LookBackAction = MakeAction(EInputActionValueType::Boolean);
	MappingContext->MapKey(LookBackAction, EKeys::Q);
	MappingContext->MapKey(LookBackAction, EKeys::MiddleMouseButton);
	UInputAction* FlashlightAction = MakeAction(EInputActionValueType::Boolean);
	MappingContext->MapKey(FlashlightAction, EKeys::F);
	UInputAction* FocusAction = MakeAction(EInputActionValueType::Boolean);
	MappingContext->MapKey(FocusAction, EKeys::RightMouseButton);
	UInputAction* InteractAction = MakeAction(EInputActionValueType::Boolean);
	MappingContext->MapKey(InteractAction, EKeys::E);
	MappingContext->MapKey(InteractAction, EKeys::LeftMouseButton);

	Input->BindAction(MoveAction, ETriggerEvent::Triggered, this, &ARelentlessCharacter::Move);
	Input->BindAction(MoveAction, ETriggerEvent::Completed, this, &ARelentlessCharacter::StopMove);
	Input->BindAction(LookAction, ETriggerEvent::Triggered, this, &ARelentlessCharacter::Look);
	Input->BindAction(SprintAction, ETriggerEvent::Started, this, &ARelentlessCharacter::SprintPressed);
	Input->BindAction(SprintAction, ETriggerEvent::Completed, this, &ARelentlessCharacter::SprintReleased);
	Input->BindAction(CrouchAction, ETriggerEvent::Started, this, &ARelentlessCharacter::CrouchPressed);
	Input->BindAction(CrouchAction, ETriggerEvent::Completed, this, &ARelentlessCharacter::CrouchReleased);
	Input->BindAction(JumpAction, ETriggerEvent::Started, this, &ARelentlessCharacter::JumpPressed);
	Input->BindAction(JumpAction, ETriggerEvent::Completed, this, &ACharacter::StopJumping);
	Input->BindAction(LookBackAction, ETriggerEvent::Started, this, &ARelentlessCharacter::LookBackPressed);
	Input->BindAction(LookBackAction, ETriggerEvent::Completed, this, &ARelentlessCharacter::LookBackReleased);
	Input->BindAction(FlashlightAction, ETriggerEvent::Started, this, &ARelentlessCharacter::ToggleFlashlight);
	Input->BindAction(FocusAction, ETriggerEvent::Started, this, &ARelentlessCharacter::FocusPressed);
	Input->BindAction(FocusAction, ETriggerEvent::Completed, this, &ARelentlessCharacter::FocusReleased);
	Input->BindAction(InteractAction, ETriggerEvent::Started, this, &ARelentlessCharacter::InteractPressed);
	Input->BindAction(InteractAction, ETriggerEvent::Completed, this, &ARelentlessCharacter::InteractReleased);

	if (APlayerController* PC = Cast<APlayerController>(GetController()))
	{
		if (UEnhancedInputLocalPlayerSubsystem* Subsystem = ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(PC->GetLocalPlayer()))
		{
			Subsystem->AddMappingContext(MappingContext, 0);
		}
	}
}

void ARelentlessCharacter::Move(const FInputActionValue& Value)
{
	MoveInput = Value.Get<FVector2D>();
	const FRotator YawRotation(0.f, GetControlRotation().Yaw, 0.f);
	AddMovementInput(FRotationMatrix(YawRotation).GetUnitAxis(EAxis::X), MoveInput.Y);
	AddMovementInput(FRotationMatrix(YawRotation).GetUnitAxis(EAxis::Y), MoveInput.X);
}

void ARelentlessCharacter::StopMove(const FInputActionValue& Value)
{
	MoveInput = FVector2D::ZeroVector;
}

void ARelentlessCharacter::Look(const FInputActionValue& Value)
{
	const FVector2D Axis = Value.Get<FVector2D>();
	// Steering is clumsy while you're staring behind you.
	const float YawScale = FMath::Lerp(1.f, 0.35f, LookBackAlpha);
	AddControllerYawInput(Axis.X * YawScale);
	AddControllerPitchInput(-Axis.Y * YawScale);
}

void ARelentlessCharacter::CrouchPressed()
{
	bCrouchHeld = true;
	Crouch();
}

void ARelentlessCharacter::CrouchReleased()
{
	bCrouchHeld = false;
	if (!bForcedCrouch)
	{
		UnCrouch();
	}
}

void ARelentlessCharacter::JumpPressed()
{
	if (!bIsCrouched)
	{
		Jump();
	}
}

void ARelentlessCharacter::ToggleFlashlight()
{
	if (bDead)
	{
		return;
	}
	bFlashlightOn = !bFlashlightOn && Battery > 0.f;
	if (FlashlightClickSound)
	{
		UGameplayStatics::PlaySound2D(this, FlashlightClickSound);
	}
}

void ARelentlessCharacter::InteractPressed()
{
	AActor* Target = FocusedActor.Get();
	if (IChaseInteractable* Interactable = Cast<IChaseInteractable>(Target))
	{
		InteractingActor = Target;
		Interactable->BeginInteract(this);
	}
}

void ARelentlessCharacter::InteractReleased()
{
	if (IChaseInteractable* Interactable = Cast<IChaseInteractable>(InteractingActor.Get()))
	{
		Interactable->EndInteract(this);
	}
	InteractingActor = nullptr;
}

void ARelentlessCharacter::SetForcedCrouch(bool bForce)
{
	bForcedCrouch = bForce;
	if (bForce)
	{
		Crouch();
	}
	else if (!bCrouchHeld)
	{
		// Movement keeps retrying until there's headroom.
		UnCrouch();
	}
}

// ---------------------------------------------------------------------------
// Per-frame
// ---------------------------------------------------------------------------

void ARelentlessCharacter::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

	if (!bDead)
	{
		UpdateMovement(DeltaTime);
		UpdateInteractTarget();
	}
	UpdateFlashlight(DeltaTime);
	UpdateCamera(DeltaTime);
}

float ARelentlessCharacter::GetDanger() const
{
	const UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>();
	return Chase ? Chase->GetDanger() : 0.f;
}

void ARelentlessCharacter::UpdateMovement(float DeltaTime)
{
	const bool bMoving = GetVelocity().Size2D() > 50.f;
	const bool bForward = MoveInput.Y > -0.1f;
	bSprinting = bSprintHeld && bMoving && bForward && !bIsCrouched && !bExhausted;

	float Speed = WalkSpeed;
	if (bSprinting)
	{
		Speed = SprintSpeed;
	}
	else if (bSprintHeld && bExhausted && bMoving)
	{
		Speed = ExhaustedSpeed;
	}
	Speed *= FMath::Lerp(1.f, LookBackSpeedScale, LookBackAlpha);
	GetCharacterMovement()->MaxWalkSpeed = Speed;

	const UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>();
	const bool bInChase = Chase && Chase->IsChaseActive();
	if (bSprinting)
	{
		Stamina -= (bInChase ? ChaseSprintDrain : SprintDrain) * DeltaTime;
		if (Stamina <= 0.f)
		{
			Stamina = 0.f;
			bExhausted = true;
		}
	}
	else
	{
		Stamina = FMath::Min(MaxStamina, Stamina + StaminaRegen * (bExhausted ? 0.8f : 1.f) * DeltaTime);
		if (bExhausted && Stamina >= ExhaustedRecoverAt)
		{
			bExhausted = false;
		}
	}
}

void ARelentlessCharacter::UpdateFlashlight(float DeltaTime)
{
	const float Danger = GetDanger();
	const float Time = GetWorld()->GetTimeSeconds();
	const bool bLit = bFlashlightOn && Battery > 0.f;
	const bool bFocusing = bLit && bFocusHeld && !bDead;

	if (bLit)
	{
		Battery = FMath::Max(0.f, Battery - (bFocusing ? FocusDrain : BatteryDrain) * DeltaTime);
		if (Battery <= 0.f)
		{
			bFlashlightOn = false;
		}
	}

	float Intensity = FlashlightLumens * (bFocusing ? FocusMultiplier : 1.f);
	const float Charge = Battery / MaxBattery;
	if (Charge < 0.2f)
	{
		Intensity *= FMath::Lerp(0.35f, 1.f, Charge / 0.2f);
	}

	// The light gets unreliable as it gets closer, and when the battery is dying.
	// Driven by danger, not randomness, so the flicker itself becomes a warning.
	const float Instability = FMath::Max(FMath::Clamp((Danger - 0.55f) / 0.45f, 0.f, 1.f), Charge < 0.1f ? 0.6f : 0.f);
	if (Instability > 0.f)
	{
		const float Noise = FMath::PerlinNoise1D(Time * 11.f) * 0.5f + 0.5f;
		if (Noise > 1.f - 0.45f * Instability)
		{
			Intensity *= 0.06f;
		}
	}

	Flashlight->SetVisibility(bLit);
	Flashlight->SetIntensity(Intensity);
	const float TargetOuter = bFocusing ? FocusOuterCone : OuterCone;
	Flashlight->SetOuterConeAngle(FMath::FInterpTo(Flashlight->OuterConeAngle, TargetOuter, DeltaTime, 10.f));
	Flashlight->SetInnerConeAngle(Flashlight->OuterConeAngle * 0.45f);

	if (bFocusing)
	{
		TryStunPursuer();
	}
}

void ARelentlessCharacter::TryStunPursuer()
{
	const UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>();
	APursuerCharacter* Pursuer = Chase ? Chase->GetPursuer() : nullptr;
	if (!Pursuer || !Pursuer->IsActiveThreat())
	{
		return;
	}

	const FVector From = Camera->GetComponentLocation();
	const FVector ToHead = Pursuer->GetHeadLocation() - From;
	if (ToHead.Size() > StunRange)
	{
		return;
	}
	const float CosAngle = FVector::DotProduct(ToHead.GetSafeNormal(), Camera->GetForwardVector());
	if (CosAngle < FMath::Cos(FMath::DegreesToRadians(FocusOuterCone * 0.8f)))
	{
		return;
	}

	FCollisionQueryParams Params(SCENE_QUERY_STAT(FlashlightStun), false, this);
	Params.AddIgnoredActor(Pursuer);
	FHitResult Hit;
	if (!GetWorld()->LineTraceSingleByChannel(Hit, From, Pursuer->GetHeadLocation(), ECC_Visibility, Params))
	{
		Pursuer->TryStun();
	}
}

void ARelentlessCharacter::UpdateCamera(float DeltaTime)
{
	const float Danger = GetDanger();
	const float Time = GetWorld()->GetTimeSeconds();
	FRotator View;

	if (bDead)
	{
		// Forced to look at it.
		View = LastViewRotation;
		if (const APursuerCharacter* Killer = KilledBy.Get())
		{
			const FRotator Desired = (Killer->GetHeadLocation() - Camera->GetComponentLocation()).Rotation();
			View = FMath::RInterpTo(LastViewRotation, Desired, DeltaTime, 8.f);
		}
	}
	else
	{
		LookBackAlpha = FMath::FInterpTo(LookBackAlpha, bLookBackHeld ? 1.f : 0.f, DeltaTime, LookBackBlendSpeed);
		const float Ease = FMath::InterpEaseInOut(0.f, 1.f, LookBackAlpha, 2.f);

		View = GetControlRotation().GetNormalized();
		View.Yaw += LookBackYaw * Ease;
		View.Pitch = FMath::Lerp(View.Pitch, View.Pitch * 0.3f, Ease);
	}

	// Head bob scales with speed.
	const float Speed2D = GetVelocity().Size2D();
	const float BobAmount = bDead ? 0.f : FMath::Clamp(Speed2D / SprintSpeed, 0.f, 1.f);
	if (GetCharacterMovement()->IsMovingOnGround() && Speed2D > 20.f)
	{
		BobPhase += DeltaTime * Speed2D * 0.022f;
	}
	const float BobZ = FMath::Sin(BobPhase * 2.f) * 2.6f * BobAmount;
	const float BobY = FMath::Sin(BobPhase) * 1.5f * BobAmount;
	View.Roll += FMath::Sin(BobPhase) * 0.9f * BobAmount;

	// Fear shake: subtle until it's right behind you.
	const float ShakeStrength = Danger * Danger * 1.4f;
	View.Pitch += FMath::PerlinNoise1D(Time * 7.f) * ShakeStrength;
	View.Yaw += FMath::PerlinNoise1D(Time * 7.f + 31.f) * ShakeStrength;
	if (bExhausted)
	{
		View.Pitch += FMath::Sin(Time * 2.4f) * 0.9f;
	}

	// Eye height is tracked from the feet so crouching eases instead of snapping.
	EyeHeight = FMath::FInterpTo(EyeHeight, bIsCrouched ? CrouchedEyeHeight : StandingEyeHeight, DeltaTime, 10.f);
	const float HalfHeight = GetCapsuleComponent()->GetScaledCapsuleHalfHeight();
	Camera->SetRelativeLocation(FVector(0.f, BobY, EyeHeight - HalfHeight + BobZ));
	Camera->SetWorldRotation(View);
	LastViewRotation = View;

	const float TargetFOV = BaseFOV + (bSprinting ? SprintFOVBoost : 0.f) + Danger * 4.f;
	Camera->SetFieldOfView(FMath::FInterpTo(Camera->FieldOfView, TargetFOV, DeltaTime, 6.f));

	FPostProcessSettings& PP = Camera->PostProcessSettings;
	PP.VignetteIntensity = 0.45f + 0.65f * Danger;
	PP.FilmGrainIntensity = 0.15f + 0.45f * Danger;
	PP.SceneFringeIntensity = Danger * 3.f;
	const float Saturation = bExhausted ? 0.55f : FMath::Lerp(0.9f, 0.7f, Danger);
	PP.ColorSaturation = FVector4(Saturation, Saturation, Saturation, 1.f);
}

void ARelentlessCharacter::UpdateInteractTarget()
{
	FocusedActor = nullptr;

	const FVector Start = Camera->GetComponentLocation();
	const FVector End = Start + Camera->GetForwardVector() * InteractRange;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(Interact), false, this);
	FHitResult Hit;
	if (GetWorld()->LineTraceSingleByChannel(Hit, Start, End, ECC_Visibility, Params))
	{
		const IChaseInteractable* Interactable = Cast<IChaseInteractable>(Hit.GetActor());
		if (Interactable && Interactable->CanInteract())
		{
			FocusedActor = Hit.GetActor();
		}
	}
}

// ---------------------------------------------------------------------------
// Death and checkpoints
// ---------------------------------------------------------------------------

void ARelentlessCharacter::Caught(APursuerCharacter* Killer)
{
	if (bDead)
	{
		return;
	}
	bDead = true;
	KilledBy = Killer;
	InteractReleased();

	APlayerController* PC = Cast<APlayerController>(GetController());
	if (PC)
	{
		DisableInput(PC);
	}
	GetCharacterMovement()->StopMovementImmediately();
	GetCharacterMovement()->DisableMovement();
	if (DeathSound)
	{
		UGameplayStatics::PlaySound2D(this, DeathSound);
	}

	FTimerHandle FadeTimer;
	GetWorldTimerManager().SetTimer(FadeTimer, FTimerDelegate::CreateWeakLambda(this, [this]()
	{
		if (APlayerController* Controller = Cast<APlayerController>(GetController()))
		{
			Controller->PlayerCameraManager->StartCameraFade(0.f, 1.f, 0.5f, FLinearColor::Black, true, true);
		}
	}), 0.9f, false);

	if (UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>())
	{
		Chase->NotifyPlayerCaught();
	}
}

void ARelentlessCharacter::Respawn(const FTransform& Where)
{
	SetActorLocation(Where.GetLocation(), false, nullptr, ETeleportType::TeleportPhysics);
	const FRotator Facing(0.f, Where.Rotator().Yaw, 0.f);
	SetActorRotation(Facing);

	bDead = false;
	KilledBy = nullptr;
	bSprintHeld = bCrouchHeld = bForcedCrouch = bLookBackHeld = bFocusHeld = false;
	bExhausted = false;
	MoveInput = FVector2D::ZeroVector;
	LookBackAlpha = 0.f;
	Stamina = MaxStamina;
	Battery = FMath::Max(Battery, MaxBattery * 0.4f);
	bFlashlightOn = true;
	UnCrouch();
	GetCharacterMovement()->SetMovementMode(MOVE_Walking);

	if (APlayerController* PC = Cast<APlayerController>(GetController()))
	{
		PC->SetControlRotation(Facing);
		EnableInput(PC);
		PC->PlayerCameraManager->StartCameraFade(1.f, 0.f, 1.2f, FLinearColor::Black, true, false);
	}
	LastViewRotation = Facing;
}

void ARelentlessCharacter::AddBattery(float Amount)
{
	Battery = FMath::Min(MaxBattery, Battery + Amount);
}

void ARelentlessCharacter::ShowHint(const FText& Text, float Duration)
{
	HintText = Text;
	HintDuration = FMath::Max(Duration, 0.5f);
	HintEndTime = GetWorld()->GetTimeSeconds() + HintDuration;
}

float ARelentlessCharacter::GetHintAlpha() const
{
	const float Remaining = HintEndTime - GetWorld()->GetTimeSeconds();
	const float Elapsed = HintDuration - Remaining;
	return FMath::Clamp(FMath::Min(Remaining, Elapsed) / 0.5f, 0.f, 1.f);
}

FText ARelentlessCharacter::GetInteractPrompt() const
{
	const AActor* Target = InteractingActor.IsValid() ? InteractingActor.Get() : FocusedActor.Get();
	const IChaseInteractable* Interactable = Cast<IChaseInteractable>(Target);
	return Interactable ? Interactable->GetInteractPrompt() : FText::GetEmpty();
}

float ARelentlessCharacter::GetInteractProgress() const
{
	const IChaseInteractable* Interactable = Cast<IChaseInteractable>(InteractingActor.Get());
	return Interactable ? Interactable->GetInteractProgress() : -1.f;
}

FVector ARelentlessCharacter::GetFeetLocation() const
{
	return GetActorLocation() - FVector(0.f, 0.f, GetCapsuleComponent()->GetScaledCapsuleHalfHeight());
}

FVector ARelentlessCharacter::GetEyeLocation() const
{
	return Camera->GetComponentLocation();
}

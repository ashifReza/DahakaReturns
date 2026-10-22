#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "ChaseSubsystem.generated.h"

class APursuerCharacter;
class ARelentlessCharacter;
class AChaseTrigger;
class AVentZone;

DECLARE_MULTICAST_DELEGATE(FOnChaseEvent);

// Owns the state of a chase: who is chasing whom, the current checkpoint, and
// the single "danger" value (0..1) that drives music, camera and lights.
UCLASS()
class RELENTLESS_API UChaseSubsystem : public UTickableWorldSubsystem
{
	GENERATED_BODY()

public:
	virtual void Tick(float DeltaTime) override;
	virtual TStatId GetStatId() const override { RETURN_QUICK_DECLARE_CYCLE_STAT(UChaseSubsystem, STATGROUP_Tickables); }

	void RegisterPursuer(APursuerCharacter* InPursuer) { Pursuer = InPursuer; }
	void RegisterPlayer(ARelentlessCharacter* InPlayer) { Player = InPlayer; }

	// Starts the chase, or just moves the checkpoint if one is already running.
	void StartChase(AChaseTrigger* Trigger);
	void EndChase();
	void NotifyPlayerCaught();
	void RestartFromCheckpoint();

	void PlayerEnteredCrawlspace(AVentZone* Zone);
	void PlayerExitedCrawlspace(AVentZone* Zone);

	float GetDanger() const { return Danger; }
	bool IsChaseActive() const { return bChaseActive; }
	APursuerCharacter* GetPursuer() const { return Pursuer.Get(); }
	ARelentlessCharacter* GetPlayer() const { return Player.Get(); }

	FOnChaseEvent OnChaseStarted;
	FOnChaseEvent OnChaseEnded;
	FOnChaseEvent OnChaseReset;

	// Gap (cm along the pursuer's trail) at which danger is 1 and 0.
	float DangerNearGap = 200.f;
	float DangerFarGap = 2000.f;
	float RestartDelay = 2.2f;
	float RestartGrace = 1.5f;

private:
	void ActivatePursuer();

	TWeakObjectPtr<APursuerCharacter> Pursuer;
	TWeakObjectPtr<ARelentlessCharacter> Player;

	bool bChaseActive = false;
	bool bHasCheckpoint = false;
	FTransform PlayerRespawn;
	FTransform PursuerStart;
	float Danger = 0.f;

	FTimerHandle PursuerTimer;
	FTimerHandle RestartTimer;
};

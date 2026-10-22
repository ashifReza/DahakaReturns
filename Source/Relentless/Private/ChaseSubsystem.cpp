#include "ChaseSubsystem.h"
#include "ChaseTrigger.h"
#include "PursuerCharacter.h"
#include "RelentlessCharacter.h"
#include "VentZone.h"
#include "Kismet/GameplayStatics.h"
#include "TimerManager.h"

void UChaseSubsystem::Tick(float DeltaTime)
{
	float Target = 0.f;
	APursuerCharacter* P = Pursuer.Get();
	if (bChaseActive && P)
	{
		if (P->IsActiveThreat())
		{
			const float Pct = (P->GetTrailGap() - DangerNearGap) / (DangerFarGap - DangerNearGap);
			Target = 1.f - FMath::Clamp(Pct, 0.f, 1.f);
		}
		else if (P->GetState() == EPursuerState::Lost)
		{
			// You can't see it, but it's still out there.
			Target = 0.35f;
		}
	}
	// Rise fast, fall slowly: relief should take a moment to arrive.
	Danger = FMath::FInterpTo(Danger, Target, DeltaTime, Target > Danger ? 4.f : 1.f);
}

void UChaseSubsystem::StartChase(AChaseTrigger* Trigger)
{
	if (!Trigger)
	{
		return;
	}
	bHasCheckpoint = true;
	PlayerRespawn = Trigger->GetPlayerRespawnWorld();
	PursuerStart = Trigger->GetPursuerStartWorld();

	if (bChaseActive)
	{
		return;
	}
	bChaseActive = true;
	if (APursuerCharacter* P = Pursuer.Get())
	{
		P->ResetTo(PursuerStart);
		GetWorld()->GetTimerManager().SetTimer(PursuerTimer, this, &UChaseSubsystem::ActivatePursuer, FMath::Max(Trigger->ActivationDelay, 0.01f), false);
	}
	OnChaseStarted.Broadcast();
}

void UChaseSubsystem::EndChase()
{
	if (!bChaseActive)
	{
		return;
	}
	bChaseActive = false;
	GetWorld()->GetTimerManager().ClearTimer(PursuerTimer);
	if (APursuerCharacter* P = Pursuer.Get())
	{
		P->Retreat();
	}
	OnChaseEnded.Broadcast();
}

void UChaseSubsystem::NotifyPlayerCaught()
{
	GetWorld()->GetTimerManager().ClearTimer(PursuerTimer);
	GetWorld()->GetTimerManager().SetTimer(RestartTimer, this, &UChaseSubsystem::RestartFromCheckpoint, RestartDelay, false);
}

void UChaseSubsystem::RestartFromCheckpoint()
{
	if (!bHasCheckpoint)
	{
		UGameplayStatics::OpenLevel(this, FName(*UGameplayStatics::GetCurrentLevelName(this)));
		return;
	}
	if (ARelentlessCharacter* PC = Player.Get())
	{
		PC->Respawn(PlayerRespawn);
	}
	if (APursuerCharacter* P = Pursuer.Get())
	{
		P->ResetTo(PursuerStart);
	}
	OnChaseReset.Broadcast();

	bChaseActive = true;
	Danger = 0.f;
	GetWorld()->GetTimerManager().SetTimer(PursuerTimer, this, &UChaseSubsystem::ActivatePursuer, RestartGrace, false);
}

void UChaseSubsystem::ActivatePursuer()
{
	if (APursuerCharacter* P = Pursuer.Get(); P && bChaseActive)
	{
		P->Activate();
	}
}

void UChaseSubsystem::PlayerEnteredCrawlspace(AVentZone* Zone)
{
	if (APursuerCharacter* P = Pursuer.Get(); P && bChaseActive)
	{
		P->LosePlayer();
	}
}

void UChaseSubsystem::PlayerExitedCrawlspace(AVentZone* Zone)
{
	APursuerCharacter* P = Pursuer.Get();
	ARelentlessCharacter* PC = Player.Get();
	if (!P || !PC || !Zone || !bChaseActive || P->GetState() != EPursuerState::Lost)
	{
		return;
	}

	// Came out the far end: it finds another way round. Backed out: it was waiting.
	const FTransform Ambush = Zone->GetAmbushWorld();
	const FVector PlayerLoc = PC->GetActorLocation();
	const bool bFarSide = FVector::Dist(PlayerLoc, Ambush.GetLocation()) < FVector::Dist(PlayerLoc, P->GetActorLocation());

	TWeakObjectPtr<APursuerCharacter> WeakP = P;
	FTimerDelegate Delegate = FTimerDelegate::CreateWeakLambda(this, [WeakP, Ambush, bFarSide]()
	{
		if (APursuerCharacter* Pursuer = WeakP.Get(); Pursuer && Pursuer->GetState() == EPursuerState::Lost)
		{
			if (bFarSide)
			{
				Pursuer->Reappear(Ambush);
			}
			else
			{
				Pursuer->ResumeChase();
			}
		}
	});
	GetWorld()->GetTimerManager().SetTimer(PursuerTimer, Delegate, bFarSide ? Zone->AmbushDelay : 0.3f, false);
}

#include "SafeZone.h"
#include "ChaseSubsystem.h"
#include "RelentlessCharacter.h"
#include "Components/BoxComponent.h"
#include "Kismet/GameplayStatics.h"
#include "TimerManager.h"

ASafeZone::ASafeZone()
{
	Box = CreateDefaultSubobject<UBoxComponent>(TEXT("Box"));
	SetRootComponent(Box);
	Box->SetBoxExtent(FVector(400.f, 400.f, 300.f));
	Box->SetCollisionProfileName(TEXT("Trigger"));
	Box->ShapeColor = FColor::Green;
	Box->OnComponentBeginOverlap.AddDynamic(this, &ASafeZone::OnOverlap);
}

void ASafeZone::OnOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor, UPrimitiveComponent* OtherComp, int32 OtherBodyIndex, bool bFromSweep, const FHitResult& SweepResult)
{
	ARelentlessCharacter* Player = Cast<ARelentlessCharacter>(OtherActor);
	if (bReached || !Player || Player->IsDead())
	{
		return;
	}
	bReached = true;

	if (UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>())
	{
		Chase->EndChase();
	}
	if (!Message.IsEmpty())
	{
		Player->ShowHint(Message, 5.f);
	}
	if (!NextLevel.IsNone())
	{
		FTimerHandle Timer;
		GetWorldTimerManager().SetTimer(Timer, FTimerDelegate::CreateWeakLambda(this, [this]()
		{
			UGameplayStatics::OpenLevel(this, NextLevel);
		}), NextLevelDelay, false);
	}
}

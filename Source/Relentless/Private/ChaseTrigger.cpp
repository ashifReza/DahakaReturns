#include "ChaseTrigger.h"
#include "ChaseSubsystem.h"
#include "RelentlessCharacter.h"
#include "Components/BoxComponent.h"
#include "Kismet/GameplayStatics.h"

AChaseTrigger::AChaseTrigger()
{
	Box = CreateDefaultSubobject<UBoxComponent>(TEXT("Box"));
	SetRootComponent(Box);
	Box->SetBoxExtent(FVector(100.f, 150.f, 175.f));
	Box->SetCollisionProfileName(TEXT("Trigger"));
	Box->ShapeColor = FColor::Red;
	Box->OnComponentBeginOverlap.AddDynamic(this, &AChaseTrigger::OnOverlap);
}

void AChaseTrigger::OnOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor, UPrimitiveComponent* OtherComp, int32 OtherBodyIndex, bool bFromSweep, const FHitResult& SweepResult)
{
	ARelentlessCharacter* Player = Cast<ARelentlessCharacter>(OtherActor);
	if (bTriggered || !Player || Player->IsDead())
	{
		return;
	}
	bTriggered = true;

	if (!Hint.IsEmpty())
	{
		Player->ShowHint(Hint, HintDuration);
	}
	if (Stinger)
	{
		UGameplayStatics::PlaySound2D(this, Stinger);
	}
	if (bStartsChase)
	{
		if (UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>())
		{
			Chase->StartChase(this);
		}
	}
}

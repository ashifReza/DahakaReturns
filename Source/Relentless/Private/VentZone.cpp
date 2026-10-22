#include "VentZone.h"
#include "ChaseSubsystem.h"
#include "RelentlessCharacter.h"
#include "Components/BoxComponent.h"

AVentZone::AVentZone()
{
	Box = CreateDefaultSubobject<UBoxComponent>(TEXT("Box"));
	SetRootComponent(Box);
	Box->SetBoxExtent(FVector(800.f, 150.f, 100.f));
	Box->SetCollisionProfileName(TEXT("Trigger"));
	Box->ShapeColor = FColor::Cyan;
	Box->OnComponentBeginOverlap.AddDynamic(this, &AVentZone::OnBeginOverlap);
	Box->OnComponentEndOverlap.AddDynamic(this, &AVentZone::OnEndOverlap);
}

void AVentZone::OnBeginOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor, UPrimitiveComponent* OtherComp, int32 OtherBodyIndex, bool bFromSweep, const FHitResult& SweepResult)
{
	if (ARelentlessCharacter* Player = Cast<ARelentlessCharacter>(OtherActor))
	{
		Player->SetForcedCrouch(true);
		if (UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>())
		{
			Chase->PlayerEnteredCrawlspace(this);
		}
	}
}

void AVentZone::OnEndOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor, UPrimitiveComponent* OtherComp, int32 OtherBodyIndex)
{
	if (ARelentlessCharacter* Player = Cast<ARelentlessCharacter>(OtherActor))
	{
		Player->SetForcedCrouch(false);
		if (UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>())
		{
			Chase->PlayerExitedCrawlspace(this);
		}
	}
}

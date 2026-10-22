#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "SafeZone.generated.h"

class UBoxComponent;

// Somewhere it can't follow. Ends the chase; optionally loads the next level.
UCLASS()
class RELENTLESS_API ASafeZone : public AActor
{
	GENERATED_BODY()

public:
	ASafeZone();

	UPROPERTY(EditAnywhere, Category = "Safe Zone")
	FText Message;

	// Leave empty to stay in this level.
	UPROPERTY(EditAnywhere, Category = "Safe Zone")
	FName NextLevel;

	UPROPERTY(EditAnywhere, Category = "Safe Zone")
	float NextLevelDelay = 5.f;

protected:
	UPROPERTY(VisibleAnywhere, Category = "Safe Zone")
	TObjectPtr<UBoxComponent> Box;

	UFUNCTION()
	void OnOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor, UPrimitiveComponent* OtherComp, int32 OtherBodyIndex, bool bFromSweep, const FHitResult& SweepResult);

private:
	bool bReached = false;
};

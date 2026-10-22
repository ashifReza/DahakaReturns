#pragma once

#include "CoreMinimal.h"
#include "UObject/Interface.h"
#include "ChaseInteractable.generated.h"

class ARelentlessCharacter;

UINTERFACE(MinimalAPI, meta = (CannotImplementInterfaceInBlueprint))
class UChaseInteractable : public UInterface
{
	GENERATED_BODY()
};

// Anything the player can use with E: doors, levers, valves.
class RELENTLESS_API IChaseInteractable
{
	GENERATED_BODY()

public:
	virtual bool CanInteract() const { return true; }
	virtual FText GetInteractPrompt() const { return FText::GetEmpty(); }
	virtual void BeginInteract(ARelentlessCharacter* By) {}
	virtual void EndInteract(ARelentlessCharacter* By) {}
	// 0..1 for hold interactions, negative when there is no progress to show.
	virtual float GetInteractProgress() const { return -1.f; }
};

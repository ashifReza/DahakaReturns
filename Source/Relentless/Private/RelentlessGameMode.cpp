#include "RelentlessGameMode.h"
#include "RelentlessCharacter.h"
#include "RelentlessHUD.h"

ARelentlessGameMode::ARelentlessGameMode()
{
	DefaultPawnClass = ARelentlessCharacter::StaticClass();
	HUDClass = ARelentlessHUD::StaticClass();
}

#pragma once

#include "CoreMinimal.h"
#include "Components/StaticMeshComponent.h"
#include "Materials/MaterialInstanceDynamic.h"

// Placeholder visuals built from the engine's basic shapes, so the game runs
// with zero imported assets. Swap meshes/materials in the editor any time.
namespace Greybox
{
	inline const TCHAR* CubePath = TEXT("/Engine/BasicShapes/Cube.Cube");
	inline const TCHAR* SpherePath = TEXT("/Engine/BasicShapes/Sphere.Sphere");
	inline const TCHAR* CylinderPath = TEXT("/Engine/BasicShapes/Cylinder.Cylinder");
	inline const TCHAR* ConePath = TEXT("/Engine/BasicShapes/Cone.Cone");

	// Tints a basic-shape mesh. Leaves custom materials alone.
	inline void Tint(UStaticMeshComponent* Comp, const FLinearColor& Color)
	{
		if (!Comp)
		{
			return;
		}
		UMaterialInterface* Base = LoadObject<UMaterialInterface>(nullptr, TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
		if (!Base || Comp->GetMaterial(0) != Base)
		{
			return;
		}
		UMaterialInstanceDynamic* MID = UMaterialInstanceDynamic::Create(Base, Comp);
		MID->SetVectorParameterValue(TEXT("Color"), Color);
		Comp->SetMaterial(0, MID);
	}
}

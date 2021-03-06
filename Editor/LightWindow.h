#pragma once

class wiGUI;
class wiWindow;
class wiLabel;
class wiCheckBox;
class wiSlider;
class wiButton;
class wiColorPicker;
class wiComboBox;

class EditorComponent;

class LightWindow
{
public:
	LightWindow(EditorComponent* editor);
	~LightWindow();

	wiGUI* GUI;

	wiECS::Entity entity;
	void SetEntity(wiECS::Entity entity);

	void SetLightType(wiScene::LightComponent::LightType type);

	wiWindow*	lightWindow;
	wiSlider*	energySlider;
	wiSlider*	rangeSlider;
	wiSlider*	radiusSlider;
	wiSlider*	widthSlider;
	wiSlider*	heightSlider;
	wiSlider*	fovSlider;
	wiSlider*	biasSlider;
	wiCheckBox*	shadowCheckBox;
	wiCheckBox*	haloCheckBox;
	wiCheckBox*	volumetricsCheckBox;
	wiCheckBox*	staticCheckBox;
	wiButton*	addLightButton;
	wiColorPicker*	colorPicker;
	wiComboBox*	typeSelectorComboBox;

	wiLabel* lensflare_Label;
	wiButton* lensflare_Button[7];
};


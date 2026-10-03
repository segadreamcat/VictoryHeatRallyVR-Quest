// obj_vhrq End Step. obj_vhrq is the newest object, so its events run after every other
// object's: sample the Touch controllers here, and a button press stays "pressed" for exactly
// one full game step (Begin Step, Step and End Step of every other object).
vhrq_input();

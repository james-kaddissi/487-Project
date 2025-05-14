# 🎸 FPGA Digital Guitar Pedal
This project implements a real-time digital guitar pedal using an FPGA and VHDL. The system captures a live guitar signal, processes it using digital logic to apply audio effects like distortion or delay, and outputs the modified signal to an amplifier or speaker.

## Overview
The goal is to demonstrate real-time audio signal processing using a hardware design implemented in VHDL on an FPGA development board (e.g., Nexys A7). Effects will be selected and controlled using onboard switches and buttons.

## Features 
- Live analog audio input via ADC
- Digital audio effects:
   - LPF + Noise Gate
   - OD/Distortion
   - Delay
   - Custom Underdrive (Gain reduction)
- Audio output via DAC
- Toggleable effect control

# Code breakdown of added components (DAC pulled from Lab 5 https://github.com/byett/dsd/tree/CPE487-Spring2025/Nexys-A7/Lab-5)
### ADC

SCLK - physical clock signal from the PMODs ADC sent to sync to
LRCK - flag that indicates whether the inputted bit is for Left or Right channel
SDOUT - raw audio stream data
L_data
R_data - parallel channel audio data
reset - reset flag from ADC
data_ready - flag indicating if data is ready from ADC

1. The process waits for a rising edge on SCLK to capture data.
2. On a change of LRCK, resets the bit_count and sets data_ready high, indicating new data is available.
3. Captures SDOUT.
4. If reset is high, it clears l_reg, r_reg, and resets bit_count and data_ready.
5. L_data and R_data are assigned the values of l_reg and r_reg
6. Data_valid is the internal passing of data_ready.

### Guitar Input / Processing

clk_50MHz - clock signal for the system.
dac_MCLK, dac_LRCK, dac_SCLK, dac_SDIN - signals for the DAC to control clock and data transmission.
adc_MCLK, adc_LRCK, adc_SCLK, adc_SDOUT: Signals for the ADC to control clock and receive raw audio data.

sw - 5 switches used to control various audio effects (e.g., low-pass filter, overdrive).

btnU, btnD, btnC - buttons to adjust volume up (btnU), volume down (btnD), and reset to default volume (btnC).

led - output LEDs to indicate the current volume level (volume_level is mapped to the number of active LEDs).

### DAC

## 1. Create a new RTL project guitar_pedal in Vivado Quick Start

Create four new source files of file type VHDL called guitar_input, dac_i, adc_if, nexys_a7_constraints.xdc

Create a new constraint file of file type XDC called siren

Choose Nexys A7-100T board for the project

Click 'Finish'

Click design sources and copy the VHDL code in.

Click constraints and copy the code from nexys_a7_constraints.xdc

As an alternative, you can instead download files from Github and import them into your project when creating the project. The source file or files would still be imported during the Source step, and the constraint file or files would still be imported during the Constraints step.

## 2. Run Synthesis
## 3. Run Implementation
## 4. Generate bitstream, open hardware manager, and program device
Click 'Generate Bitstream'

Click 'Open Hardware Manager' and click 'Open Target' then 'Auto Connect'

Click 'Program Device' then xc7a100t_0 to download siren.bit to the Nexys A7-100T board

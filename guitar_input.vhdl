LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY guitar_input IS
    PORT (
        clk_50MHz : IN STD_LOGIC;

        dac_MCLK : OUT STD_LOGIC;
        dac_LRCK : OUT STD_LOGIC;
        dac_SCLK : OUT STD_LOGIC;
        dac_SDIN : OUT STD_LOGIC;

        adc_MCLK : OUT STD_LOGIC;
        adc_LRCK : OUT STD_LOGIC;
        adc_SCLK : OUT STD_LOGIC;
        adc_SDOUT : IN STD_LOGIC;

        sw : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
        btnU : IN STD_LOGIC;
        btnD : IN STD_LOGIC;     
        btnC : IN STD_LOGIC;          
        
        led : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
    );
END guitar_input;

ARCHITECTURE Behavioral OF guitar_input IS
    COMPONENT adc_if IS
        PORT (
            SCLK : IN STD_LOGIC;
            LRCK : IN STD_LOGIC;
            SDOUT : IN STD_LOGIC;
            reset : IN STD_LOGIC;
            L_data : OUT SIGNED (15 DOWNTO 0);
            R_data : OUT SIGNED (15 DOWNTO 0);
            data_valid : OUT STD_LOGIC
        );
    END COMPONENT;

    COMPONENT dac_i IS
        PORT (
            SCLK : IN STD_LOGIC;
            L_start : IN STD_LOGIC;
            R_start : IN STD_LOGIC;
            L_data : IN SIGNED (15 DOWNTO 0);
            R_data : IN SIGNED (15 DOWNTO 0);
            SDATA : OUT STD_LOGIC
        );
    END COMPONENT;

    SIGNAL counter : UNSIGNED(27 DOWNTO 0) := (OTHERS => '0');
    SIGNAL mclk_int, sclk_int, lrck_int : STD_LOGIC;
    SIGNAL reset_int : STD_LOGIC := '1';
    SIGNAL reset_done : STD_LOGIC := '0';

    SIGNAL adc_L_data, adc_R_data : SIGNED(15 DOWNTO 0);
    SIGNAL adc_data_valid : STD_LOGIC;
    SIGNAL dac_load_L, dac_load_R : STD_LOGIC;
    SIGNAL dac_L_data, dac_R_data : SIGNED(15 DOWNTO 0);
    SIGNAL dac_data_out : STD_LOGIC := '0';
    
    SIGNAL pre_scaled_input : SIGNED(15 DOWNTO 0);
    SIGNAL lowpass_L_data : SIGNED(15 DOWNTO 0);
    SIGNAL previous_L_data : SIGNED(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL prev_sample_2 : SIGNED(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL prev_sample_3 : SIGNED(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL gated_L_data : SIGNED(15 DOWNTO 0);
    SIGNAL volume_adjusted_data : SIGNED(15 DOWNTO 0);
    SIGNAL effect_output : SIGNED(15 DOWNTO 0);
    SIGNAL processed_L_data : SIGNED(15 DOWNTO 0);
    SIGNAL final_output : SIGNED(15 DOWNTO 0);
    
    CONSTANT LP_FILTER_STRENGTH : INTEGER := 4;  -- Increased filter strength (was 2)
    CONSTANT NOISE_THRESHOLD : INTEGER := 77;    -- Reduced by 15% (was 90)
    CONSTANT INPUT_ATTENUATION : INTEGER := 3;
    
    SIGNAL volume_level : INTEGER RANGE 0 TO 16 := 8;
    
    SIGNAL btnU_prev, btnD_prev : STD_LOGIC := '0';
    SIGNAL btn_counter : UNSIGNED(19 DOWNTO 0) := (OTHERS => '0');
    SIGNAL btn_ready : STD_LOGIC := '1';
    
    TYPE delay_buffer_type IS ARRAY(0 TO 8191) OF SIGNED(15 DOWNTO 0); 
    SIGNAL delay_buffer : delay_buffer_type := (OTHERS => (OTHERS => '0'));
    SIGNAL delay_write_ptr : INTEGER RANGE 0 TO 8191 := 0;
    SIGNAL delay_read_ptr : INTEGER RANGE 0 TO 8191 := 0;
    SIGNAL delay_output : SIGNED(15 DOWNTO 0);
    SIGNAL delay_fb_signal : SIGNED(15 DOWNTO 0);
    CONSTANT DELAY_LENGTH : INTEGER := 4000;
    CONSTANT DELAY_FB_AMOUNT : INTEGER := 2;
    CONSTANT DELAY_MIX : INTEGER := 1;
    
    SIGNAL overdrive_input : SIGNED(15 DOWNTO 0);
    SIGNAL overdrive_output : SIGNED(15 DOWNTO 0);
    SIGNAL previous_overdrive : SIGNED(15 DOWNTO 0) := (OTHERS => '0');
    CONSTANT OVERDRIVE_GAIN : INTEGER := 2;
    CONSTANT OVERDRIVE_THRESHOLD : INTEGER := 10000;
    
    SIGNAL underdrive_output : SIGNED(15 DOWNTO 0);
    SIGNAL previous_underdrive : SIGNED(15 DOWNTO 0) := (OTHERS => '0');
    CONSTANT UNDERDRIVE_ATTEN : INTEGER := 2;
    CONSTANT UNDERDRIVE_SMOOTH : INTEGER := 1;
    
BEGIN
    process(clk_50MHz)
        VARIABLE abs_sample : INTEGER;
        VARIABLE filter_acc : SIGNED(19 DOWNTO 0); -- Widened to 20 bits for more headroom
    begin
        if rising_edge(clk_50MHz) then
            counter <= counter + 1;
            
            if reset_done = '0' then
                reset_int <= '1';
                reset_done <= '1';
            else
                reset_int <= '0';
            end if;
            
            btn_counter <= btn_counter + 1;
            if btn_counter = 0 then
                btn_ready <= '1';
                btnU_prev <= btnU;
                btnD_prev <= btnD;
                
                if btnU = '1' and btnU_prev = '0' and btn_ready = '1' then
                    if volume_level < 16 then volume_level <= volume_level + 1; end if;
                    btn_ready <= '0';
                end if;
                
                if btnD = '1' and btnD_prev = '0' and btn_ready = '1' then
                    if volume_level > 0 then volume_level <= volume_level - 1; end if;
                    btn_ready <= '0';
                end if;
                
                if btnC = '1' and btn_ready = '1' then
                    volume_level <= 8;
                    btn_ready <= '0';
                end if;
            end if;
            
            led <= (OTHERS => '0');
            for i in 0 to 15 loop
                if i < volume_level then led(i) <= '1'; end if;
            end loop;
            
            pre_scaled_input <= SHIFT_RIGHT(adc_L_data, INPUT_ATTENUATION);
            
            if sw(0) = '1' then
                filter_acc := RESIZE(pre_scaled_input, 20) + 
                             RESIZE(previous_L_data * 3, 20) +
                             RESIZE(prev_sample_2 * 2, 20) +
                             RESIZE(prev_sample_3, 20);
                             
                lowpass_L_data <= RESIZE(SHIFT_RIGHT(filter_acc, 3), 16);  -- Divide by 8
                
                prev_sample_3 <= prev_sample_2;
                prev_sample_2 <= previous_L_data;
                previous_L_data <= pre_scaled_input;
            else
                lowpass_L_data <= pre_scaled_input;
                previous_L_data <= pre_scaled_input;
                prev_sample_2 <= pre_scaled_input;
                prev_sample_3 <= pre_scaled_input;
            end if;
            
            if sw(1) = '1' then
                if lowpass_L_data(15) = '1' then
                    abs_sample := TO_INTEGER(NOT lowpass_L_data) + 1;
                else
                    abs_sample := TO_INTEGER(lowpass_L_data);
                end if;
                
                if abs_sample < NOISE_THRESHOLD/3 then
                    gated_L_data <= (OTHERS => '0');
                elsif abs_sample < NOISE_THRESHOLD then
                    gated_L_data <= RESIZE(SHIFT_RIGHT(lowpass_L_data * 
                                   TO_SIGNED((abs_sample - NOISE_THRESHOLD/3) * 3, 16), 8), 16);
                else
                    gated_L_data <= lowpass_L_data;
                end if;
            else
                gated_L_data <= lowpass_L_data;
            end if;
            
            case volume_level is
                when 0 => volume_adjusted_data <= (OTHERS => '0');
                when 1 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 7);
                when 2 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 6);
                when 3 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 5);
                when 4 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 4);
                when 5 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 4) + SHIFT_RIGHT(gated_L_data, 5);
                when 6 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 3);
                when 7 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 3) + SHIFT_RIGHT(gated_L_data, 4);
                when 8 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 2);
                when 9 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 2) + SHIFT_RIGHT(gated_L_data, 3);
                when 10 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 1) - SHIFT_RIGHT(gated_L_data, 3);
                when 11 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 1) - SHIFT_RIGHT(gated_L_data, 4);
                when 12 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 1);
                when 13 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 1) + SHIFT_RIGHT(gated_L_data, 3);
                when 14 => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 1) + SHIFT_RIGHT(gated_L_data, 2);
                when 15 => volume_adjusted_data <= gated_L_data - SHIFT_RIGHT(gated_L_data, 3);
                when 16 => volume_adjusted_data <= gated_L_data;
                when others => volume_adjusted_data <= SHIFT_RIGHT(gated_L_data, 2);
            end case;
            
            if sw(2) = '1' then
                -- Overdrive Effect
                overdrive_input <= SHIFT_LEFT(volume_adjusted_data, OVERDRIVE_GAIN);
                
                if overdrive_input > TO_SIGNED(OVERDRIVE_THRESHOLD, 16) then
                    overdrive_output <= TO_SIGNED(OVERDRIVE_THRESHOLD, 16) + 
                                      SHIFT_RIGHT(overdrive_input - TO_SIGNED(OVERDRIVE_THRESHOLD, 16), 2);
                elsif overdrive_input < TO_SIGNED(-OVERDRIVE_THRESHOLD, 16) then
                    overdrive_output <= TO_SIGNED(-OVERDRIVE_THRESHOLD, 16) + 
                                      SHIFT_RIGHT(overdrive_input - TO_SIGNED(-OVERDRIVE_THRESHOLD, 16), 2);
                else
                    overdrive_output <= overdrive_input;
                end if;
                
                effect_output <= SHIFT_RIGHT(overdrive_output + previous_overdrive, 1);
                previous_overdrive <= overdrive_output;
                previous_underdrive <= overdrive_output;
            elsif sw(4) = '1' then

                underdrive_output <= SHIFT_RIGHT(volume_adjusted_data, UNDERDRIVE_ATTEN);
                
                effect_output <= SHIFT_RIGHT(underdrive_output + previous_underdrive, 1);
                
                previous_underdrive <= underdrive_output;
                previous_overdrive <= previous_underdrive;  -- Keep in sync
            else
                effect_output <= volume_adjusted_data;
                previous_overdrive <= volume_adjusted_data;
                previous_underdrive <= volume_adjusted_data;
            end if;
            
            processed_L_data <= effect_output;
            
            if sw(3) = '1' then
                if delay_write_ptr >= DELAY_LENGTH then
                    delay_read_ptr <= delay_write_ptr - DELAY_LENGTH;
                else
                    delay_read_ptr <= (delay_write_ptr + 8192) - DELAY_LENGTH;
                end if;
                
                delay_output <= processed_L_data + SHIFT_RIGHT(delay_buffer(delay_read_ptr), DELAY_MIX);
                
                delay_fb_signal <= SHIFT_RIGHT(delay_buffer(delay_read_ptr), DELAY_FB_AMOUNT);
                
                delay_buffer(delay_write_ptr) <= processed_L_data + delay_fb_signal;
                
                if delay_write_ptr = 8191 then
                    delay_write_ptr <= 0;
                else
                    delay_write_ptr <= delay_write_ptr + 1;
                end if;
                
                final_output <= delay_output;
            else
                delay_buffer(delay_write_ptr) <= processed_L_data;
                
                if delay_write_ptr = 8191 then
                    delay_write_ptr <= 0;
                else
                    delay_write_ptr <= delay_write_ptr + 1;
                end if;
                
                final_output <= processed_L_data;
            end if;
        end if;
    end process;

    mclk_int <= counter(1);  -- 12.5 MHz
    sclk_int <= counter(3);  -- 6.25 MHz
    lrck_int <= counter(9);  -- 48.8 kHz

    dac_MCLK <= mclk_int;
    dac_SCLK <= sclk_int;
    dac_LRCK <= lrck_int;
    adc_MCLK <= mclk_int;
    adc_SCLK <= sclk_int;
    adc_LRCK <= lrck_int;
    dac_SDIN <= dac_data_out;

    process(sclk_int)
    begin
        if falling_edge(sclk_int) then
            dac_load_L <= '1' when counter(9 downto 4) = "000001" else '0';
            dac_load_R <= '1' when counter(9 downto 4) = "100001" else '0';
        end if;
    end process;

    dac_L_data <= final_output;
    dac_R_data <= final_output;

    adc : adc_if
        PORT MAP (
            SCLK => sclk_int,
            LRCK => lrck_int,
            SDOUT => adc_SDOUT,
            reset => reset_int,
            L_data => adc_L_data,
            R_data => adc_R_data,
            data_valid => adc_data_valid
        );

    dac : dac_i
        PORT MAP (
            SCLK => sclk_int,
            L_start => dac_load_L,
            R_start => dac_load_R,
            L_data => dac_L_data,
            R_data => dac_R_data,
            SDATA => dac_data_out
        );

END Behavioral;

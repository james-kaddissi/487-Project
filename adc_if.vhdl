


LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY adc_if IS
    PORT (
        SCLK : IN STD_LOGIC;
        LRCK : IN STD_LOGIC;
        SDOUT : IN STD_LOGIC;
        reset : IN STD_LOGIC;
        L_data : OUT SIGNED (15 DOWNTO 0);
        R_data : OUT SIGNED (15 DOWNTO 0);
        data_valid : OUT STD_LOGIC
    );
END adc_if;

ARCHITECTURE Behavioral OF adc_if IS
    SIGNAL l_reg : STD_LOGIC_VECTOR (15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL r_reg : STD_LOGIC_VECTOR (15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL bit_count : INTEGER RANGE 0 TO 16 := 0;
    SIGNAL lrck_prev : STD_LOGIC := '0';
    SIGNAL data_ready : STD_LOGIC := '0';
BEGIN
    capture_proc : PROCESS
    BEGIN
        WAIT UNTIL rising_edge(SCLK);
        
        lrck_prev <= LRCK;
        
        IF lrck_prev /= LRCK THEN
            bit_count <= 0;
            data_ready <= '1';
        ELSE
            data_ready <= '0';
        END IF;
        
        IF bit_count < 16 THEN
            IF LRCK = '0' THEN
                l_reg <= l_reg(14 DOWNTO 0) & SDOUT;
            ELSE
                r_reg <= r_reg(14 DOWNTO 0) & SDOUT;
            END IF;
            bit_count <= bit_count + 1;
        END IF;
        
        IF reset = '1' THEN
            l_reg <= (OTHERS => '0');
            r_reg <= (OTHERS => '0');
            bit_count <= 0;
            data_ready <= '0';
        END IF;
    END PROCESS;
    
    L_data <= signed(l_reg);
    R_data <= signed(r_reg);
    data_valid <= data_ready;
    
END Behavioral;

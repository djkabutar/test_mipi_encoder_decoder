**MIPI to Multiple Peripheral**

Using IP of MIPI CSI-2 rx & tx to receive data and convert those data to multiple peripheral 
like UART, I2C, SPI, 1-Wire.

Currently supported FPGAs are Trion family of the Efinix, which consists of the direct IP of 
the MIPI CSI. Here, as of the MIPI IP of the efinix 64-bit packet is being received at
every clock cycle. For different Color Formats the data representation changes.

Here, `RGB888` format is used.

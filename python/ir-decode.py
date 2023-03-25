import pandas as pd
from datetime import timedelta as td
with open("logic-analyzer-measurement.csv", "rb") as f:
    # read the binary data
    header = f.readline()    # metadata header
header = header.split(b',')
header = header[2].split(b'=')
header = header[1].strip(b's\r\n')
tInc_s = float(header.strip())


irData = pd.read_csv("logic-analyzer-measurement.csv", usecols=['D7-D0'])
irData = irData.rename({'D7-D0': 'ir_out'}, axis=1)
irData['ir_out'] = irData['ir_out'].str.split('x').str[1]
irData.index = irData.index * tInc_s   # row indices is time in milliseconds

# irDataResampled = irData.resample(seconds=td.seconds(tInc_s*1000))

irData.to_csv('decoded-output.csv')

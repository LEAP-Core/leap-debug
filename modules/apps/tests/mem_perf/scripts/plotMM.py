#!/usr/bin/env python

from optparse import OptionParser
import cmath
import sys

parser = OptionParser()
(options, args) = parser.parse_args()

if len(args) < 1:
  sys.exit(-1)


datain = open(args[0], "r");
writebw = open("writebw.dat", "w")
readbw = open("readbw.dat", "w")
readlatency = open("readlatency.dat", "w")

writebwExcel = open("writebw.txt", "w")
readbwExcel = open("readbw.txt", "w")
readlatencyExcel = open("readlatency.txt", "w")

# need to convert components 3 to a linear scale.
scale = {"1": "0", "2": "1", "3": "2", "4": "3", "5": "4", "6": "5", "7": "6", "8": "7", "16": "8", "32": "9", "64": "10", "128": "11"}
scale2 = {"512": "0", "1024": "1", "2048": "2", "4096": "3", "8192": "4", "16384": "5", 
          "32768": "6", "65536": "7", "131072": "8", "262144": "9", "524288": "10", "1048576": "11", "2097152": "12", 
          "4194304": "13", "8388608": "14"}

readbwArray = {}
readlatencyArray = {}
writebwArray = {}
strides = []
workingSets = ["512", "1024", "2048", "4096", "8192", "16384", "32768", "65536", "131072", "262144", 
               "524288", "1048576", "2097152", "4194304", "8388608"]
is_write = False

for line in datain.readlines():
    components = line.split(':')
    print str(components)    

    if (len(components) == 3 and components[1] == " Write Working Set"):
          is_write = True
    elif (len(components) == 3 and components[1] == " Read Working Set"):
          is_write = False
    elif (len(components) == 1 and components[0] == "Warmup\n"):
          is_write = None
    
    # Adler insert a warmup phase
    if(is_write is None):
        continue 

    # if (len(components) == 11):
    #     print components
    
    if(len(components) == 11 and is_write == True):
        if (components[2] == '0'):
            continue
        bw = str(1/(int(components[8])/1.0/(1 << 18)))
        writebw.write(scale2[components[2]] + " " + scale[components[4]]  + " " + bw + "\n")
        if(not components[4] in writebwArray):
            writebwArray[components[4]] = {}
            readbwArray[components[4]] = {}
            readlatencyArray[components[4]] = {}
            strides.append(components[4])
        writebwArray[components[4]][components[2]] = bw
      
    if(len(components) == 11 and is_write == False):
        if (components[2] == '0'):
            continue
        bw = str(1/(int(components[8])/1.0/(1 << 18)))
        latency = str((int(components[6])/1.0/(1 << 18)))
        readbw.write(scale2[components[2]] + " " + scale[components[4]]  + " " + bw + "\n")
        readlatency.write(scale2[components[2]] + " " + scale[components[4]]  + " " + latency + "\n")
        readbwArray[components[4]][components[2]] = bw
        readlatencyArray[components[4]][components[2]] = latency

def printAll(str):
    writebwExcel.write(str)
    readbwExcel.write(str)
    readlatencyExcel.write(str)

printAll(" ;")
  
for stride in strides:
    printAll(stride + ";")

printAll("\n")

for workingSet in workingSets:
    printAll(workingSet + ";")
    for stride in strides:
        writebwExcel.write(writebwArray[stride][workingSet] + ";")
        readbwExcel.write(readbwArray[stride][workingSet] + ";")
        readlatencyExcel.write(readlatencyArray[stride][workingSet] + ";")
    printAll("\n")






import sys, csv
formulas=[l.rstrip("\n") for l in open(sys.argv[1],encoding="utf-8") if l.strip()]
data={ (0,5):"apple",(1,5):"banana",(2,5):"apple",(3,5):"cherry",(4,5):"5",
       (0,6):"10",(1,6):"20",(2,6):"30",(3,6):"40",(4,6):"50",(5,6):"60"}
w=csv.writer(sys.stdout,lineterminator="\n")
for i,f in enumerate(formulas):
    row=["="+f.replace(";",",")]+[""]*7
    for c in range(1,8):
        if (i,c) in data: row[c]=data[(i,c)]
    w.writerow(row)

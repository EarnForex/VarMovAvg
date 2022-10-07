//+------------------------------------------------------------------+
//|                                                    VarMovAvg.mq4 |
//|                                 Copyright © 2008-2022, EarnForex |
//|                                       https://www.earnforex.com/ |
//|               Based on Var_Mov_Avg3.mq4 by GOODMAN & Mstera & AF |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2008-2022, EarnForex"
#property link      "https://www.earnforex.com/metatrader-indicators/Var-Mov-Avg/"
#property version   "1.02"
#property strict

#property description "VarMovAvg - a mathematical superposition on the standard Moving Average approach."
#property description "Green dots signal bullish trend. Red dots signal bearish trend."

#property indicator_chart_window
#property indicator_buffers 3
#property indicator_color1 clrSienna
#property indicator_type1  DRAW_LINE
#property indicator_width1 2
#property indicator_label1 "VarMovAvg"
#property indicator_color2 clrGreen
#property indicator_type2  DRAW_ARROW
#property indicator_width2 2
#property indicator_color3 clrRed
#property indicator_type3  DRAW_ARROW
#property indicator_width3 2

enum ENUM_CANDLE_TO_CHECK
{
    Current,
    Previous
};

input int    periodAMA = 50;
input int    nfast = 15;
input int    nslow = 10;
input double G = 1.0;
input double dK = 0.1;
input bool   EnableNativeAlerts = false;
input bool   EnableEmailAlerts = false;
input bool   EnablePushAlerts = false;
input ENUM_CANDLE_TO_CHECK TriggerCandle = Previous;
input ENUM_TIMEFRAMES UpperTimeframe = PERIOD_CURRENT;

// Buffers:
double AMAbuffer[];
double AMAupsig[];
double AMAdownsig[];

// For MTF support:
string IndicatorFileName;

// Global variables:
double slowSC, fastSC, dSC;

void OnInit()
{
    SetIndexArrow(1, 159);
    SetIndexArrow(2, 159);

    SetIndexDrawBegin(0, periodAMA + 2);
    SetIndexDrawBegin(1, periodAMA + 2);
    SetIndexDrawBegin(2, periodAMA + 2);
    
    SetIndexBuffer(0, AMAbuffer);
    SetIndexBuffer(1, AMAupsig);
    SetIndexBuffer(2, AMAdownsig);
    
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0);
    
    slowSC = 2.0 / (nslow + 1);
    fastSC = 2.0 / (nfast + 1);
    dSC = fastSC - slowSC;
    
    if (PeriodSeconds(UpperTimeframe) < PeriodSeconds())
    {
        Print("UpperTimeframe should be above the current timeframe.");
        IndicatorFileName = "";
    }
    else if (PeriodSeconds(UpperTimeframe) > PeriodSeconds()) IndicatorFileName = WindowExpertName();
    else IndicatorFileName = "";
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if (Bars <= periodAMA + 2) return 0; // Not enough bars.

    int counted_bars = IndicatorCounted();
    if ((counted_bars > 0) && (IndicatorFileName != "")) counted_bars -= PeriodSeconds(UpperTimeframe) / PeriodSeconds(); // Make the indicator redraw all current bars that constitute the upper timeframe bar.
    int limit = Bars - counted_bars;

    if (limit > Bars - periodAMA - 2) limit = Bars - periodAMA - 2;

    for (int pos = limit; pos >= 0; pos--)
    {
        if (IndicatorFileName != "") // Higher timeframe data.
        {
            int shift = iBarShift(Symbol(), UpperTimeframe, Time[pos]); // Get the upper timeframe shift based on the current timeframe bar's time.
            AMAbuffer[pos] = iCustom(Symbol(), UpperTimeframe, IndicatorFileName, periodAMA, nfast, nslow, G, dK, false, false, false, TriggerCandle, UpperTimeframe, 0, shift);
            AMAupsig[pos] = iCustom(Symbol(), UpperTimeframe, IndicatorFileName, periodAMA, nfast, nslow, G, dK, false, false, false, TriggerCandle, UpperTimeframe, 1, shift);
            AMAdownsig[pos] = iCustom(Symbol(), UpperTimeframe, IndicatorFileName, periodAMA, nfast, nslow, G, dK, false, false, false, TriggerCandle, UpperTimeframe, 2, shift);
        }
        else // Normal calculation.
        {
            double AMA0;

            if (pos == Bars - periodAMA - 2) AMA0 = Close[pos + 1];
            else AMA0 = AMAbuffer[pos + 1];

            double signal = MathAbs(Close[pos] - Close[pos + periodAMA]);

            double noise = 0.000000001; // To avoid division by zero if it is unchanged.

            for (int i = 0; i < periodAMA; i++)
            {
                noise += MathAbs(Close[pos + i] - Close[pos + i + 1]);
            }

            double ER = signal / noise;
            double ERSC = ER * dSC;
            double SSC = ERSC + slowSC;
            double ddK = MathPow(SSC, G) * (Close[pos] - AMA0);
            double AMA = AMA0 + ddK;

            AMAbuffer[pos] = AMA;
            if ((MathAbs(ddK) > dK * Point()) && (ddK > 0)) AMAupsig[pos] = AMA;
            else AMAupsig[pos] = 0;
            if ((MathAbs(ddK) > dK * Point()) && (ddK < 0)) AMAdownsig[pos] = AMA;
            else AMAdownsig[pos] = 0;

            AMA0 = AMA;
        }
    }

    static int prev_Signal = 0;
    static datetime LastAlertTime = 0;
    int Signal = 0;
    if (TriggerCandle == Previous)
    {
        if (IndicatorFileName == "") // Non-MTF:
        {
            // Change between the previous bar and the bar before it.
            if ((AMAupsig[1]   > 0) && (AMAupsig[2]   == 0)) Signal =  1; // Bullish
            if ((AMAdownsig[1] > 0) && (AMAdownsig[2] == 0)) Signal = -1; // Bearish
        }
        else // MTF:
        {
            // Change between the previous bar and the bar before it.
            if ((iCustom(Symbol(), UpperTimeframe, IndicatorFileName, periodAMA, nfast, nslow, G, dK, false, false, false, TriggerCandle, UpperTimeframe, 1, 1) > 0) && (iCustom(Symbol(), UpperTimeframe, IndicatorFileName, periodAMA, nfast, nslow, G, dK, false, false, false, TriggerCandle, UpperTimeframe, 1, 2) == 0)) Signal =  1; // Bullish
            if ((iCustom(Symbol(), UpperTimeframe, IndicatorFileName, periodAMA, nfast, nslow, G, dK, false, false, false, TriggerCandle, UpperTimeframe, 2, 1) > 0) && (iCustom(Symbol(), UpperTimeframe, IndicatorFileName, periodAMA, nfast, nslow, G, dK, false, false, false, TriggerCandle, UpperTimeframe, 2, 2) == 0)) Signal = -1; // Bearish
        }
    }
    else
    {
        // Change between the current color of the latest bar and the previous signal.
        if ((AMAupsig[0]   > 0) && (prev_Signal !=  1)) Signal =  1; // Bullish
        if ((AMAdownsig[0] > 0) && (prev_Signal != -1)) Signal = -1; // Bearish
    }
    if ((LastAlertTime > 0) && (((TriggerCandle > 0) && (Time[0] > LastAlertTime)) || (TriggerCandle == 0)))
    {
        string Text;
        // Buy signal.
        if ((Signal == 1) && (prev_Signal != 1))
        {
            Text = "VarMovAvg: " + Symbol() + " - " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7) + " - Up Signal.";
            if (EnableNativeAlerts) Alert(Text);
            if (EnableEmailAlerts) SendMail("VarMovAvg Alert", Text);
            if (EnablePushAlerts) SendNotification(Text);
            LastAlertTime = Time[0];
            prev_Signal = Signal;
        }
        // Sell signal.
        else if ((Signal == -1) && (prev_Signal != -1))
        {
            Text = "VarMovAvg: " + Symbol() + " - " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7) + " - Down Signal.";
            if (EnableNativeAlerts) Alert(Text);
            if (EnableEmailAlerts) SendMail("VarMovAvg Alert", Text);
            if (EnablePushAlerts) SendNotification(Text);
            LastAlertTime = Time[0];
            prev_Signal = Signal;
        }
    }

    if (LastAlertTime == 0)
    {
        LastAlertTime = Time[0];
        prev_Signal = Signal;
    }

    return rates_total;
}
//+------------------------------------------------------------------+
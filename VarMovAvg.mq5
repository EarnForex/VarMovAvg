//+------------------------------------------------------------------+
//|                                                    VarMovAvg.mq5 |
//|                                  Copyright © 2009-2022 EarnForex |
//|                                       https://www.earnforex.com/ |
//|               Based on Var_Mov_Avg3.mq4 by GOODMAN & Mstera & AF |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2009-2022, EarnForex"
#property link      "https://www.earnforex.com/metatrader-indicators/Var-Mov-Avg/"
#property version   "1.02"

#property description "VarMovAvg - a mathematical superposition on the standard Moving Average approach."
#property description "Green dots signal bullish trend. Red dots signal bearish trend."

#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   2
#property indicator_type1 DRAW_LINE
#property indicator_type2 DRAW_COLOR_ARROW
#property indicator_color1 clrSienna
#property indicator_color2 clrGreen, clrRed, clrNONE
#property indicator_width1  2
#property indicator_width2  10

enum ENUM_CANDLE_TO_CHECK
{
    Current,
    Previous
};

input int    periodAMA = 50;
input int    nfast     = 15;
input int    nslow     = 10;
input double G         = 1.0;
input double dK        = 0.1;
input bool   EnableNativeAlerts = false;
input bool   EnableEmailAlerts = false;
input bool   EnablePushAlerts = false;
input ENUM_CANDLE_TO_CHECK TriggerCandle = Previous;
input ENUM_TIMEFRAMES UpperTimeframe = PERIOD_CURRENT;

// Buffers:
double AMAbuffer[];
double AMAsig[];
double AMAsigcol[];

// For MTF support:
string IndicatorFileName;
int VMA_handle;

// Global variables:
double slowSC, fastSC, dSC;

void OnInit()
{
    IndicatorSetString(INDICATOR_SHORTNAME, "VarMovAvg");
    IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

    PlotIndexSetInteger(1, PLOT_ARROW, 159);

    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0);

    PlotIndexGetInteger(0, PLOT_DRAW_BEGIN, periodAMA + 2);
    PlotIndexGetInteger(1, PLOT_DRAW_BEGIN, periodAMA + 2);

    SetIndexBuffer(0, AMAbuffer, INDICATOR_DATA);
    SetIndexBuffer(1, AMAsig,    INDICATOR_DATA);
    SetIndexBuffer(2, AMAsigcol, INDICATOR_COLOR_INDEX);

    slowSC = 2.0 / (nslow + 1);
    fastSC = 2.0 / (nfast + 1);
    dSC = fastSC - slowSC;

    if (PeriodSeconds(UpperTimeframe) < PeriodSeconds())
    {
        Print("UpperTimeframe should be above the current timeframe.");
        IndicatorFileName = "";
        VMA_handle = INVALID_HANDLE;
    }
    else if (PeriodSeconds(UpperTimeframe) > PeriodSeconds())
    {
        IndicatorFileName = MQLInfoString(MQL_PROGRAM_NAME);
        VMA_handle = iCustom(Symbol(), UpperTimeframe, IndicatorFileName, periodAMA, nfast, nslow, G, dK, false, false, false, TriggerCandle, UpperTimeframe);
    }
    else
    {
        IndicatorFileName = "";
        VMA_handle = INVALID_HANDLE;
    }
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &Time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &Close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if (rates_total <= periodAMA + 2) return 0;

    ArraySetAsSeries(Close, true);
    ArraySetAsSeries(Time, true);
    bool rec_only_latest_upper_bar = false; // Recalculate only the latest upper timeframe bar.
    int counted_bars = prev_calculated;
    if ((counted_bars > 0) && (VMA_handle != INVALID_HANDLE))
    {
        counted_bars -= PeriodSeconds(UpperTimeframe) / PeriodSeconds(); // Make the indicator redraw all current bars that constitute the upper timeframe bar.
        rec_only_latest_upper_bar = true;
    }
    int limit = rates_total - counted_bars;
    

    if (limit > rates_total - periodAMA - 2) limit = rates_total - periodAMA - 2;
    for (int pos = limit; pos >= 0; pos--)
    {
        if (VMA_handle != INVALID_HANDLE) // Higher timeframe data.
        {
            double buf[1];
            if (rec_only_latest_upper_bar)
                if (Time[pos] <  iTime(Symbol(), UpperTimeframe, 0)) continue; // Skip bars older than the upper current bar.
            int n = CopyBuffer(VMA_handle, 0, Time[pos], 1, buf);
            if (n == 1) AMAbuffer[rates_total - pos - 1] = buf[0];
            else return prev_calculated;
            n = CopyBuffer(VMA_handle, 1, Time[pos], 1, buf);
            if (n == 1) AMAsig[rates_total - pos - 1] = buf[0];
            else return prev_calculated;
            n = CopyBuffer(VMA_handle, 2, Time[pos], 1, buf);
            if (n == 1) AMAsigcol[rates_total - pos - 1] = buf[0];
            else return prev_calculated;
        }
        else // Normal calculation.
        {
            double AMA0;

            if (pos == rates_total - periodAMA - 2) AMA0 = Close[pos + 1];
            else AMA0 = AMAbuffer[rates_total - pos - 2];

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

            AMAbuffer[rates_total - pos - 1] = AMA;
            AMAsig[rates_total - pos - 1] = AMA;
            if ((MathAbs(ddK) > dK * _Point) && (ddK > 0)) AMAsigcol[rates_total - pos - 1] = 0;
            else if ((MathAbs(ddK) > dK * _Point) && (ddK < 0)) AMAsigcol[rates_total - pos - 1] = 1;
            else AMAsigcol[rates_total - pos - 1] = 2;

            AMA0 = AMA;
        }
    }

    if ((!EnableNativeAlerts) && (!EnableEmailAlerts) && (!EnablePushAlerts)) return rates_total; // No need to go further.

    // Alerts
    static int prev_Signal = 0;
    static datetime LastAlertTime = 0;
    int Signal = 0;
    if (TriggerCandle == Previous)
    {
        if (VMA_handle == INVALID_HANDLE) // Non-MTF:
        {
            // Change between the previous bar and the bar before it.
            if ((AMAsigcol[rates_total - 2] == 0) && (AMAsigcol[rates_total - 3] != 0)) Signal =  1; // Bullish
            if ((AMAsigcol[rates_total - 2] == 1) && (AMAsigcol[rates_total - 3] != 1)) Signal = -1; // Bearish
        }
        else // MTF:
        {
            double buf[2];
            int n = CopyBuffer(VMA_handle, 2, 1, 2, buf); // Third buffer. Two latest _finished_ bars.
            if (n == 2)
            {
                // Change between the previous bar and the bar before it.
                if ((buf[1] == 0) && (buf[0] != 0)) Signal =  1; // Bullish
                if ((buf[1] == 1) && (buf[0] != 1)) Signal = -1; // Bearish
            }
        }
    } // TriggerCandle == Current
    else
    {
        // Change between the current color of the latest bar and the previous signal.
        if ((AMAsigcol[rates_total - 1] == 0) && (prev_Signal !=  1)) Signal =  1; // Bullish
        if ((AMAsigcol[rates_total - 1] == 1) && (prev_Signal != -1)) Signal = -1; // Bearish
    }
    if ((LastAlertTime > 0) && (((TriggerCandle > 0) && (Time[0] > LastAlertTime)) || (TriggerCandle == 0)))
    {
        string Text, TextNative;
        // Buy signal.
        if ((Signal == 1) && (prev_Signal != 1))
        {
            Text = "VarMovAvg: " + Symbol() + " - " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7) + " - Up Signal.";
            TextNative = "VarMovAvg: Up Signal.";
            if (EnableNativeAlerts) Alert(TextNative);
            if (EnableEmailAlerts) SendMail("VarMovAvg Alert", Text);
            if (EnablePushAlerts) SendNotification(Text);
            LastAlertTime = Time[0];
            prev_Signal = Signal;
        }
        // Sell signal.
        else if ((Signal == -1) && (prev_Signal != -1))
        {
            Text = "VarMovAvg: " + Symbol() + " - " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7) + " - Down Signal.";
            TextNative = "VarMovAvg: Down Signal.";
            if (EnableNativeAlerts) Alert(TextNative);
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
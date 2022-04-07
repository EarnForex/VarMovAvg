//+------------------------------------------------------------------+
//|                                                    VarMovAvg.mq5 |
//|                                  Copyright © 2009-2022 EarnForex |
//|                                       https://www.earnforex.com/ |
//|               Based on Var_Mov_Avg3.mq4 by GOODMAN & Mstera & AF |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2009-2022, EarnForex"
#property link      "https://www.earnforex.com/metatrader-indicators/Var-Mov-Avg/"
#property version   "1.01"

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

enum enum_candle_to_check
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
input enum_candle_to_check TriggerCandle = Previous;

datetime LastAlertTime = D'01.01.1970';

double AMAbuffer[];
double AMAsig[];
double AMAsigcol[];

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
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
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

    int counted_bars = prev_calculated;
    if (counted_bars > 0) counted_bars--;
    int limit = rates_total - counted_bars;

    if (limit > rates_total - periodAMA - 2) limit = rates_total - periodAMA - 2;

    for (int pos = limit; pos >= 0; pos--)
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

    // Alerts
    if (((TriggerCandle > 0) && (time[rates_total - 1] > LastAlertTime)) || (TriggerCandle == 0))
    {
        string Text, TextNative;
        // Buy signal.
        if ((AMAsigcol[rates_total - 1 - TriggerCandle] == 0) && (AMAsigcol[rates_total - 2 - TriggerCandle] != 0))
        {
            Text = "VarMovAvg: " + Symbol() + " - " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7) + " - Up Signal.";
            TextNative = "VarMovAvg: Up Signal.";
            if (EnableNativeAlerts) Alert(TextNative);
            if (EnableEmailAlerts) SendMail("VarMovAvg Alert", Text);
            if (EnablePushAlerts) SendNotification(Text);
            LastAlertTime = time[rates_total - 1];
        }
        // Sell signal.
        if ((AMAsigcol[rates_total - 1 - TriggerCandle] == 1) && (AMAsigcol[rates_total - 2 - TriggerCandle] != 1))
        {
            Text = "VarMovAvg: " + Symbol() + " - " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7) + " - Down Signal.";
            TextNative = "VarMovAvg: Down Signal.";
            if (EnableNativeAlerts) Alert(TextNative);
            if (EnableEmailAlerts) SendMail("VarMovAvg Alert", Text);
            if (EnablePushAlerts) SendNotification(Text);
            LastAlertTime = time[rates_total - 1];
        }
    }

    return rates_total;
}
//+------------------------------------------------------------------+
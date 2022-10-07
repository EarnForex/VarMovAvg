// -------------------------------------------------------------------------------
//   
// VarMovAvg - a mathematical superposition on the standard Moving Average approach.
// Green dots signal bullish trend. Red dots signal bearish trend.
//    
// Version 1.02
// Copyright 2009-2022, EarnForex.com
// https://www.earnforex.com/metatrader-indicators/Var-Mov-Avg/
// -------------------------------------------------------------------------------
using System;
using cAlgo.API;
using cAlgo.API.Indicators;

namespace cAlgo.Indicators
{
    [Indicator(IsOverlay = true, TimeZone = TimeZones.UTC, AccessRights = AccessRights.None)]
    public class VarMovAvg : Indicator
    {
        public enum ENUM_CANDLE_TO_CHECK
        {
            Current,
            Previous
        }
        
        [Parameter(DefaultValue = 50)]
        public int periodAMA { get; set; }

        [Parameter(DefaultValue = 15)]
        public int nfast { get; set; }

        [Parameter(DefaultValue = 10)]
        public int nslow { get; set; }

        [Parameter(DefaultValue = 1.0)]
        public double G { get; set; }

        [Parameter(DefaultValue = 0.1)]
        public double dK { get; set; }

        [Parameter("Enable email alerts", DefaultValue = false)]
        public bool EnableEmailAlerts { get; set; }

        [Parameter("AlertEmail: Email From", DefaultValue = "")]
        public string AlertEmailFrom { get; set; }

        [Parameter("AlertEmail: Email To", DefaultValue = "")]
        public string AlertEmailTo { get; set; }

        [Parameter("Trigger candle", DefaultValue = ENUM_CANDLE_TO_CHECK.Previous)]
        public ENUM_CANDLE_TO_CHECK TriggerCandle { get; set; }

        [Parameter("Upper timeframe")]
        public TimeFrame UpperTimeframe { get; set; }

        [Output("VarMovAvg", LineColor = "Sienna", Thickness = 2)]
        public IndicatorDataSeries AMAbuffer { get; set; }

        [Output("Up", PlotType = PlotType.Points, LineColor = "Green", Thickness = 5)]
        public IndicatorDataSeries AMAupsig { get; set; }

        [Output("Down", PlotType = PlotType.Points, LineColor = "Red", Thickness = 5)]
        public IndicatorDataSeries AMAdownsig { get; set; }

        private double slowSC, fastSC, dSC;
        private bool UseUpperTimeFrame;

        private Bars customBars;

        private bool first = true; // Was the first buffer value assigned already?
        private int prev_index = -1;
        private int prev_Signal = 0;
        private DateTime LastAlertTime, unix_epoch;
        
        protected override void Initialize()
        {
            slowSC = 2.0 / (nslow + 1);
            fastSC = 2.0 / (nfast + 1);
            dSC = fastSC - slowSC;
            
            if (UpperTimeframe <= TimeFrame)
            {
                Print("UpperTimeframe <= current timeframe. Ignored.");
                UseUpperTimeFrame = false;
                customBars = Bars;
            }
            else
            {
                UseUpperTimeFrame = true;
                customBars = MarketData.GetBars(UpperTimeframe);
            }
            LastAlertTime = new DateTime(1970, 1, 1, 0, 0, 0);
            unix_epoch = new DateTime(1970, 1, 1, 0, 0, 0);
        }
        
        public override void Calculate(int index)
        {
            int customIndex = index;
            int cnt = 0; // How many bars of the current timeframe should be recalculated.
            if (UseUpperTimeFrame)
            {
                customIndex = customBars.OpenTimes.GetIndexByTime(Bars.OpenTimes[index]);
                // Find how many current timeframe bars should be recalculated:
                while (customBars.OpenTimes.GetIndexByTime(Bars.OpenTimes[index - cnt]) == customIndex)
                {
                    cnt++;
                }
            }
            
            if (customIndex < periodAMA) return; // Too early to calculate anything.
          
            double AMA0;
            if (first)
            {
                AMA0 = customBars.ClosePrices[customIndex - 1];
            }
            else AMA0 = AMAbuffer[index - 1];
            first = false;

            double signal = Math.Abs(customBars.ClosePrices[customIndex] - customBars.ClosePrices[customIndex - periodAMA]);

            double noise = 0.000000001; // To avoid division by zero if it is unchanged.

            for (int i = 0; i < periodAMA; i++)
            {
                noise += Math.Abs(customBars.ClosePrices[customIndex - i] - customBars.ClosePrices[customIndex - i - 1]);
            }

            double ER = signal / noise;
            double ERSC = ER * dSC;
            double SSC = ERSC + slowSC;
            double ddK = Math.Pow(SSC, G) * (customBars.ClosePrices[customIndex] - AMA0);
            double AMA = AMA0 + ddK;

            AMAbuffer[index] = AMA;
            if ((Math.Abs(ddK) > dK * Symbol.TickSize) && (ddK > 0)) AMAupsig[index] = AMA;
            else AMAupsig[index] = double.NaN;
            if ((Math.Abs(ddK) > dK * Symbol.TickSize) && (ddK < 0)) AMAdownsig[index] = AMA;
            else AMAdownsig[index] = double.NaN;
            
            if (UseUpperTimeFrame)
            {
                for (int i = 1; i < cnt; i++)
                {
                    AMAbuffer[index - i] = AMAbuffer[index];
                    AMAupsig[index - i] = AMAupsig[index];
                    AMAdownsig[index - i] = AMAdownsig[index];
                }
            }        

            if (!EnableEmailAlerts) return; // No need to go further.

            // Alerts
            int Signal = 0;
            if (!UseUpperTimeFrame) // Non-MTF:
            {
                if (TriggerCandle == ENUM_CANDLE_TO_CHECK.Previous)
                {
                    // Change between previous bar and the bar before it.
                    if ((AMAupsig[index   - 1] > 0) && (double.IsNaN(AMAupsig[index   - 2]))) Signal =  1; // Bullish
                    if ((AMAdownsig[index - 1] > 0) && (double.IsNaN(AMAdownsig[index - 2]))) Signal = -1; // Bearish
                }
                else
                {
                    // Change between the current color of the latest bar and the previous signal.
                    if ((AMAupsig[index]   > 0) && (prev_Signal !=  1)) Signal =  1; // Bullish
                    if ((AMAdownsig[index] > 0) && (prev_Signal != -1)) Signal = -1; // Bearish
                }
            }
            else // MTF:
            {
                if (TriggerCandle == ENUM_CANDLE_TO_CHECK.Previous)
                {
                    // Check two latest _finished_ bars of the upper timeframe.
                    // index - cnt - 1 points to the same value as at the last finished upper timeframe bar.
                    int last_bar_with_upper_tf_value = index - cnt - 1;
                    int last_finished_customIndex = customBars.OpenTimes.GetIndexByTime(Bars.OpenTimes[last_bar_with_upper_tf_value]);
                    if (last_finished_customIndex < 0) return;
                    // Find the penultimate upper TF bar:
                    int j = 1;
                    while (customBars.OpenTimes.GetIndexByTime(Bars.OpenTimes[last_bar_with_upper_tf_value - j]) == last_finished_customIndex)
                    {
                        j++;
                    }
                    int penultimate_bar_with_upper_tf_value = last_bar_with_upper_tf_value - j;
                    // Change between the previous bar and the bar before it.
                    if ((AMAupsig[last_bar_with_upper_tf_value] > 0) && (double.IsNaN(AMAupsig[penultimate_bar_with_upper_tf_value]))) Signal =  1; // Bullish
                    if ((AMAdownsig[last_bar_with_upper_tf_value] > 0) && (double.IsNaN(AMAdownsig[penultimate_bar_with_upper_tf_value]))) Signal = -1; // Bearish
                }
                else
                {
                    // Change between the current color of the latest bar and the previous signal.
                    if ((AMAupsig[index]   > 0) && (prev_Signal !=  1)) Signal =  1; // Bullish
                    if ((AMAdownsig[index] > 0) && (prev_Signal != -1)) Signal = -1; // Bearish
                }
            }
            if ((LastAlertTime > unix_epoch) && (((TriggerCandle == ENUM_CANDLE_TO_CHECK.Previous) && (Bars.OpenTimes[index] > LastAlertTime)) || (TriggerCandle == ENUM_CANDLE_TO_CHECK.Current)))
            {
                string Text;
                // Buy signal.
                if ((Signal == 1) && (prev_Signal != 1))
                {
                    Text = "VarMovAvg: " + Symbol.Name + " - " + TimeFrame.Name + " - Up Signal.";
                    Notifications.SendEmail(AlertEmailFrom, AlertEmailTo, "VarMovAvg Alert - " + Symbol.Name + " @ " + TimeFrame.Name, Text);
                    LastAlertTime = Bars.OpenTimes[index];
                    prev_Signal = Signal;
                }
                // Sell signal.
                else if ((Signal == -1) && (prev_Signal != -1))
                {
                    Text = "VarMovAvg: " + Symbol.Name + " - " + TimeFrame.Name + " - Down Signal.";
                    Notifications.SendEmail(AlertEmailFrom, AlertEmailTo, "VarMovAvg Alert - " + Symbol.Name + " @ " + TimeFrame.Name, Text);
                    LastAlertTime = Bars.OpenTimes[index];
                    prev_Signal = Signal;
                }
            }
        
            if ((LastAlertTime == unix_epoch) && (prev_index == index))
            {
                LastAlertTime = Bars.OpenTimes[index];
                prev_Signal = Signal;
            }
            prev_index = index;
        }
    }
}

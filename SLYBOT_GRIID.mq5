//+------------------------------------------------------------------+
//|                                              SLYBOT_GRIID_V1.mq5 |
//|                                                 Slybot Automacoes |
//|                                         https://www.slybot.com.br |
//+------------------------------------------------------------------+
#property copyright "Slybot Sistemas de Automacao"
#property link      "https://www.slybot.com.br"
#property version   "1.53"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <JAson.mqh>

#resource "\\Images\\slybot_final.bmp";

string API_URL    = "https://slybot.com.br/wp-json/slybot/v1/validate";
string API_SECRET = "SlyBot$SecureKey#2026!Xv8@Lm4^Qp7Zt2";

datetime last_validation = 0;
bool     license_valid   = false;

// Enumerações
enum ENUM_GRID_TYPE {
   GRID_FIXED = 0,    // Grid Fixo
   GRID_DYNAMIC = 1   // Grid Dinâmico (Contra e a Favor)
};

enum ENUM_TRIGGER_TYPE {
   TRIGGER_STATS = 0
};

input string LICENSE_KEY    = "";                  // Insira sua Licença

input group "Identificação -----------------------------------";
input string InpNomeEstrategia = "";               // Nome da Estratégia
input string InpComment     = "SLYBOT GRIID";      // Comentário
input int    InpMagicNumber = 100001;              // Número Mágico

input group "Proteção Diária ---------------------------------";
input double InpDailyLossLimit  = 1000.0;  // Limite de Loss Diário (R$)
input double InpDailyProfitLimit = 2000.0; // Limite de Gain Diário (R$)

input group "Stop / Take da Ordem Gatilho --------------------";
input double InpStopLoss   = 100000.0;     // Stop Loss do gatilho (pontos, 0 = desativado)
input double InpTakeProfit = 100000.0;     // Take Profit do gatilho (pontos, 0 = desativado)

input group "Grid --------------------------------------------";
input ENUM_GRID_TYPE InpGridType = GRID_DYNAMIC; // Tipo de Grid
input double InpGridInterval = 20000.0;    // Intervalo entre ordens do grid (pontos)
input int    InpGridLevels   = 5;          // Quantidade de níveis do grid (contra)
input double InpContractCost = 0.20;       // Custo por contrato (R$)
input bool   InpShowGridLines = true;      // Mostrar linhas do grid no gráfico

input group "Horários ----------------------------------------";
input string InpStartTime    = "09:00";    // Horário de início
input string InpEndTime      = "17:00";    // Horário de término
input string InpCloseTime    = "17:30";    // Horário para fechar posições
input bool   InpSwingTradeMode = false;    // Modo Swing Trade (ignora horários)

input group "Volume / Lotes ----------------------------------";
input double InpLotgatilho = 1.0;          // Lote da ordem gatilho
input double InpLotSize    = 1.0;          // Lote do grid

input group "Gatilho % ---------------------------------------";
input bool         tendencia           = true;          // true = a favor, false = contra tendência
input double       perc_alta           = 1.0;           // % de alta para gatilho
input double       perc_queda          = 1.0;           // % de queda para gatilho
input ENUM_TIMEFRAMES mm_tempo_grafico = PERIOD_CURRENT; // Tempo gráfico do gatilho

input ENUM_TRIGGER_TYPE InpTriggerType = TRIGGER_STATS; // Tipo de Gatilho

//--- Variáveis internas de mercado
double g_fechaAnterior, g_precoEntradaC, g_precoEntradaV, g_precoAtual, g_fechamentoBarra, g_percentualQueda, g_percentualAlta, g_aberturaDia, g_loteFinal;
int g_currentTime;      // Horário atual no formato HHMM (ex: 930 para 09:30)
int g_startTimeHHMM;    // InpStartTime convertido para HHMM int (ex: 900 para "09:00")

// Variáveis globais
CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;
COrderInfo orderInfo;
int bandHandle;
double dailyProfit = 0.0;
double weeklyProfit = 0.0;
double monthlyProfit = 0.0;
bool isNewDay = true;
bool isNewWeek = true;
bool isNewMonth = true;
datetime lastBarTime = 0;
bool robotEnabled = true;
int totalTrades = 0;
datetime lastTriggerTime = 0;
bool triggerPositionOpen = false;
double triggerEntryPrice = 0.0;
ulong triggerPositionTicket = 0;
ENUM_POSITION_TYPE triggerPositionType;
string triggerTimeStr;
double fiboLevels[];
bool panelMinimized = false;

// Variáveis para Fibonacci
double fiboHighPrice = 0;
double fiboLowPrice = DBL_MAX;
datetime fiboHighTime = 0;
datetime fiboLowTime = 0;
bool fiboLinesDrawn = false;

// Variáveis para modo Manual
ulong manualBuyOrderTicket = 0;
ulong manualSellOrderTicket = 0;

// Variáveis para debug
bool debugMode = true;
datetime lastDebugTime = 0;

// --- Variáveis do Grid ---
double gridLevelsContraBuy[];
double gridLevelsContraSell[];
bool gridLevelContraUsedBuy[];
bool gridLevelContraUsedSell[];

// --- Variáveis do Grid a Favor ---
ulong gridAFavorOrderTicketBuy = 0;
ulong gridAFavorOrderTicketSell = 0;
double gridAFavorCurrentLevelBuy = 0;
double gridAFavorCurrentLevelSell = 0;
bool gridAFavorActiveGridBuy = false;
bool gridAFavorActiveGridSell = false;
double gridAFavorLastPriceBuy = 0;
double gridAFavorLastPriceSell = 0;

// --- Variáveis para Limite Diário ---
bool dailyLimitReached = false;

// --- Variáveis para rastreamento de ordens do grid ---
struct GRID_ORDER {
   ulong ticket;
   double price;
   double takeProfit;
   string comment;
   bool isActive;
};

GRID_ORDER gridOrdersContraBuy[];
GRID_ORDER gridOrdersContraSell[];
bool gridInitialized = false;

// Enumeração para status de horário
enum ENUM_TIME_STATUS {
   TIME_INACTIVE,
   TIME_ACTIVE,
   TIME_CLOSE
};

// Estrutura para armazenar informações do painel
struct PANEL_INFO {
   string symbol;
   double currentPrice;
   double dailyProfit;
   double weeklyProfit;
   double monthlyProfit;
   int totalTrades;
   int activeTrades;
   string gridStatus;
   string triggerStatus;
   string manualOrderStatus;
};

PANEL_INFO panelInfo;

// --- Licença ---
string g_licensePlan       = "---";
string g_licenseExpiration = "---";
string g_licenseStatus     = "Validando...";
color  g_licenseColor      = clrYellow;

// --- Painel Premium ---
#define PANEL_NAME         "GRIIDPanel"
#define PANEL_HEADER_NAME  "GRIIDHeader"
#define PANEL_BODY_NAME    "GRIIDBody"
#define BTN_COLLAPSE       "GRIID_COLLAPSE"
#define PANEL_WIDTH        360
#define PANEL_HEADER_HEIGHT 40
#define PANEL_BODY_HEIGHT   300
#define PANEL_CORNER        CORNER_LEFT_UPPER

bool g_panelCollapsed = false;
bool g_botLigado      = true;
int  lineY = 0;
int  lineHeight = 16;


//+------------------------------------------------------------------+
//| Função para obter preço atual com validação e fallback           |
//+------------------------------------------------------------------+
double GetCurrentPrice() {
   double price = symbolInfo.Last();
   if(price <= 0) {
      price = symbolInfo.Bid();
      if(price <= 0) price = symbolInfo.Ask();
   }
   if(price <= 0) {
      if(symbolInfo.RefreshRates()) {
         price = symbolInfo.Last();
         if(price <= 0) {
            price = symbolInfo.Bid();
            if(price <= 0) price = symbolInfo.Ask();
         }
      }
   }
   if(price <= 0) {
      PrintFormat("ERRO CRÍTICO: Não foi possível obter preço válido para %s. Last=%.5f, Bid=%.5f, Ask=%.5f",
                  _Symbol, symbolInfo.Last(), symbolInfo.Bid(), symbolInfo.Ask());
   }
   return price;
}

//+------------------------------------------------------------------+
//| Função para remover espaços em branco no início e fim da string  |
//+------------------------------------------------------------------+
string TrimString(string str) {
   while(StringLen(str) > 0 && StringGetCharacter(str, 0) == ' ')
      str = StringSubstr(str, 1);
   while(StringLen(str) > 0 && StringGetCharacter(str, StringLen(str) - 1) == ' ')
      str = StringSubstr(str, 0, StringLen(str) - 1);
   return str;
}

//+------------------------------------------------------------------+
//| Função para converter string de horário para segundos            |
//+------------------------------------------------------------------+
int StringToTimeSeconds(string timeStr) {
   timeStr = TrimString(timeStr);
   if(StringLen(timeStr) != 5 || StringGetCharacter(timeStr, 2) != ':') {
      Print("Formato de horário inválido! Por favor, use HH:MM.");
      return -1;
   }
   int hours = (int)StringToInteger(StringSubstr(timeStr, 0, 2));
   int minutes = (int)StringToInteger(StringSubstr(timeStr, 3, 2));
   if(hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
      Print("Valores de horário inválidos! Horas: 0-23, Minutos: 0-59");
      return -1;
   }
   return hours * 3600 + minutes * 60;
}

//+------------------------------------------------------------------+
//| NOVA FUNÇÃO: Converter string "HH:MM" para int HHMM             |
//| Ex: "09:00" -> 900, "17:30" -> 1730                             |
//+------------------------------------------------------------------+
int TimeStringToHHMM(string timeStr) {
   timeStr = TrimString(timeStr);
   if(StringLen(timeStr) != 5 || StringGetCharacter(timeStr, 2) != ':') {
      Print("Formato de horário inválido em TimeStringToHHMM: ", timeStr);
      return -1;
   }
   int hours   = (int)StringToInteger(StringSubstr(timeStr, 0, 2));
   int minutes = (int)StringToInteger(StringSubstr(timeStr, 3, 2));
   if(hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
      Print("Valores de horário inválidos em TimeStringToHHMM: ", timeStr);
      return -1;
   }
   return hours * 100 + minutes;
}

//+------------------------------------------------------------------+
//| Função para verificar se o horário atual está dentro do intervalo|
//+------------------------------------------------------------------+
bool IsTimeInRange(string startTimeStr, string endTimeStr) {
   if(InpSwingTradeMode) return true;
   int startSeconds = StringToTimeSeconds(startTimeStr);
   int endSeconds   = StringToTimeSeconds(endTimeStr);
   if(startSeconds == -1 || endSeconds == -1) return false;
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int currentSeconds = now.hour * 3600 + now.min * 60 + now.sec;
   return (currentSeconds >= startSeconds && currentSeconds <= endSeconds);
}

//+------------------------------------------------------------------+
//| Função para verificar se o horário atual é igual ao especificado |
//+------------------------------------------------------------------+
bool IsTimeEqual(string timeStr) {
   if(InpSwingTradeMode) return false;
   int timeSeconds = StringToTimeSeconds(timeStr);
   if(timeSeconds == -1) return false;
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int currentSeconds = now.hour * 3600 + now.min * 60;
   return (currentSeconds >= timeSeconds && currentSeconds < timeSeconds + 60);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int GetPanelHeight()
{
   return g_panelCollapsed ? PANEL_HEADER_HEIGHT : PANEL_HEADER_HEIGHT + PANEL_BODY_HEIGHT;
}

int OnInit() {
   Print("=== INICIANDO SLYBOT GRIID ===");

   license_valid   = ValidateLicense();
   last_validation = TimeCurrent();
   if(!license_valid) Print("Licença inválida. Robô não irá operar.");

   EventSetTimer(1);

   PrintFormat("--- DIAGNÓSTICO TP --- Verificando StopLevel para %s...", _Symbol);
   long stopLevelLong = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopLevelLong < 0) {
       Print("--- DIAGNÓSTICO TP --- Erro ao obter StopLevel: ", GetLastError());
   } else {
       double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
       if(pointValue <= 0) {
          Print("--- DIAGNÓSTICO TP --- Erro ao obter o valor do ponto para o símbolo.");
          pointValue = _Point;
       }
       PrintFormat("--- DIAGNÓSTICO TP --- StopLevel para %s: %d pontos (valor ponto: %.8f)",
                   _Symbol, stopLevelLong, pointValue);
   }

   if(!symbolInfo.Name(_Symbol)) {
      Print("Falha ao configurar o símbolo: ", _Symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);

   ArrayResize(gridLevelsContraBuy,  InpGridLevels);
   ArrayResize(gridLevelsContraSell, InpGridLevels);
   ArrayResize(gridLevelContraUsedBuy,  InpGridLevels);
   ArrayResize(gridLevelContraUsedSell, InpGridLevels);
   ArrayFill(gridLevelContraUsedBuy,  0, InpGridLevels, false);
   ArrayFill(gridLevelContraUsedSell, 0, InpGridLevels, false);
   ArrayResize(gridOrdersContraBuy,  InpGridLevels);
   ArrayResize(gridOrdersContraSell, InpGridLevels);

   // *** CORREÇÃO: Pré-calcular g_startTimeHHMM uma vez na inicialização ***
   g_startTimeHHMM = TimeStringToHHMM(InpStartTime);
   if(g_startTimeHHMM == -1) {
      Print("ERRO: Horário de início inválido: ", InpStartTime, ". Usando 900 (09:00) como padrão.");
      g_startTimeHHMM = 900;
   }
   PrintFormat("Horário de início configurado: %s -> HHMM=%d", InpStartTime, g_startTimeHHMM);

   // *** Inicializar dados de mercado imediatamente para evitar valores zerados ***
   AtualizarDadosDoMercado();
   CalcularPrecosDeEntrada();

   RemoverPainel();
   CriarPainel();
   AtualizarPainel(TIME_INACTIVE);

   CalculateDailyProfit();
   CalculateWeeklyProfit();
   CalculateMonthlyProfit();

   if(InpSwingTradeMode)
      Print("MODO SWING TRADE ATIVADO - Horários de operação serão ignorados!");

   Print("SLYBOT GRIID inicializado com sucesso!");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   if(bandHandle != INVALID_HANDLE) IndicatorRelease(bandHandle);
   RemoverPainel();
   DeleteGridLines();
   if(manualBuyOrderTicket > 0)        trade.OrderDelete(manualBuyOrderTicket);
   if(manualSellOrderTicket > 0)       trade.OrderDelete(manualSellOrderTicket);
   if(gridAFavorOrderTicketBuy > 0)    trade.OrderDelete(gridAFavorOrderTicketBuy);
   if(gridAFavorOrderTicketSell > 0)   trade.OrderDelete(gridAFavorOrderTicketSell);
   Print("SLYBOT GRIID finalizado. Motivo: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
   // 🔒 Bloqueio de licença
   if(!license_valid)
   {
      AtualizarPainel(TIME_INACTIVE);
      return;
   }
   // 🔄 Revalidação a cada 20s
   if(TimeCurrent() - last_validation > 20)
   {
      license_valid   = ValidateLicense();
      last_validation = TimeCurrent();
      if(!license_valid) { AtualizarPainel(TIME_INACTIVE); return; }
   }
   // 🔴 Power OFF
   if(!g_botLigado)
   {
      AtualizarPainel(TIME_INACTIVE);
      return;
   }

   if(!robotEnabled) return;

   GerenciarHorarios();

   if(NovoCandle()) {
      AtualizarDadosDoMercado();
      CalcularPrecosDeEntrada();
      DesenharLinhas();
   }

   // *** CORREÇÃO: Garantir que preços estejam calculados mesmo sem novo candle ***
   if(g_precoEntradaC <= 0 || g_precoEntradaV <= 0) {
      AtualizarDadosDoMercado();
      CalcularPrecosDeEntrada();
   }

   if(!symbolInfo.RefreshRates()) {
      Print("Falha ao atualizar as taxas do símbolo");
      return;
   }

   // Debug a cada 5 segundos
   if(debugMode) {
      datetime currentTime = TimeCurrent();
      if(currentTime - lastDebugTime >= 5) {
         lastDebugTime = currentTime;
         DebugPrint();
      }
   }

   CheckNewTimeframes();
   CalculateDailyProfit();
   CalculateWeeklyProfit();
   CalculateMonthlyProfit();

   if(dailyLimitReached) {
      AtualizarPainel(TIME_INACTIVE);
      return;
   }
   if(CheckDailyLimits()) {
      AtualizarPainel(TIME_INACTIVE);
      return;
   }

   ENUM_TIME_STATUS timeStatus = CheckTimeStatus();

   if(!InpSwingTradeMode && timeStatus == TIME_CLOSE) {
      CloseAllPositions();
      return;
   }

   ManagePositions();

   if(!InpSwingTradeMode && timeStatus != TIME_ACTIVE) return;

   CheckGridOrdersExecution();

   if(!triggerPositionOpen) {
      CheckTriggers();
   }

   if(triggerPositionOpen) {
      ManageGrid();
      if(InpGridType == GRID_DYNAMIC) {
         UpdateAFavorLimitOrder();
      }
   }

   AtualizarPainel(timeStatus);
}


//+------------------------------------------------------------------+
//| Função de debug para imprimir informações importantes            |
//+------------------------------------------------------------------+
void DebugPrint() {
   double currentPrice = GetCurrentPrice();

   Print("=== DEBUG INFO v1.53 CORRIGIDO ===");
   PrintFormat("Preço atual: %.2f", currentPrice);
   Print("Trigger posição aberta: ", triggerPositionOpen);
   Print("Modo Swing Trade: ", InpSwingTradeMode ? "ATIVO" : "INATIVO");

   // *** NOVO: Mostrar valores críticos do trigger ***
   PrintFormat("TRIGGER VALS -> g_currentTime=%d, g_startTimeHHMM=%d, aberturaDia=%.2f, entradaC=%.2f, entradaV=%.2f, fechamentoBarra=%.2f",
               g_currentTime, g_startTimeHHMM, g_aberturaDia, g_precoEntradaC, g_precoEntradaV, g_fechamentoBarra);

   if(triggerPositionOpen) {
      Print("Tipo de posição trigger ORIGINAL: ", EnumToString(triggerPositionType));
      PrintFormat("Preço de referência ATUAL do grid: %.2f", triggerEntryPrice);
      Print("Ticket da posição trigger ORIGINAL: ", triggerPositionTicket);

      if(triggerPositionType == POSITION_TYPE_BUY) {
         for(int i = 0; i < InpGridLevels; i++)
            PrintFormat("Grid Contra Buy Nível %d: %.2f, Usado: %s", i, gridLevelsContraBuy[i], gridLevelContraUsedBuy[i] ? "SIM" : "NÃO");
         PrintFormat("Grid A Favor Buy (pendente): %.2f, Ativo: %s, Ticket: %d",
                     gridAFavorCurrentLevelBuy, gridAFavorActiveGridBuy ? "SIM" : "NÃO", gridAFavorOrderTicketBuy);
      } else {
         for(int i = 0; i < InpGridLevels; i++)
            PrintFormat("Grid Contra Sell Nível %d: %.2f, Usado: %s", i, gridLevelsContraSell[i], gridLevelContraUsedSell[i] ? "SIM" : "NÃO");
         PrintFormat("Grid A Favor Sell (pendente): %.2f, Ativo: %s, Ticket: %d",
                     gridAFavorCurrentLevelSell, gridAFavorActiveGridSell ? "SIM" : "NÃO", gridAFavorOrderTicketSell);
      }
   }

   int posCount = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(positionInfo.SelectByIndex(i)) {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber) {
            posCount++;
            PrintFormat("Posição #%d: Ticket=%d, Tipo=%s, Preço=%.2f, TP=%.2f, SL=%.2f, Comentário=%s",
                        posCount, positionInfo.Ticket(),
                        EnumToString((ENUM_POSITION_TYPE)positionInfo.PositionType()),
                        positionInfo.PriceOpen(), positionInfo.TakeProfit(),
                        positionInfo.StopLoss(), positionInfo.Comment());
         }
      }
   }

   Print("=== FIM DEBUG ===");
}

//+------------------------------------------------------------------+
//| Função para verificar execução de ordens do grid e resetar flags |
//+------------------------------------------------------------------+
void CheckGridOrdersExecution() {
   for(int i = 0; i < InpGridLevels; i++) {
      if(gridOrdersContraBuy[i].isActive) {
         bool positionExists = false;
         if(positionInfo.SelectByTicket(gridOrdersContraBuy[i].ticket))
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
               positionExists = true;
         if(!positionExists) {
            gridLevelContraUsedBuy[i]      = false;
            gridOrdersContraBuy[i].isActive = false;
            PrintFormat("Nível do grid contra (compra) resetado: Nível %d, Preço: %.2f", i, gridLevelsContraBuy[i]);
            if(InpShowGridLines) UpdateGridLines();
         }
      }
   }
   for(int i = 0; i < InpGridLevels; i++) {
      if(gridOrdersContraSell[i].isActive) {
         bool positionExists = false;
         if(positionInfo.SelectByTicket(gridOrdersContraSell[i].ticket))
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
               positionExists = true;
         if(!positionExists) {
            gridLevelContraUsedSell[i]      = false;
            gridOrdersContraSell[i].isActive = false;
            PrintFormat("Nível do grid contra (venda) resetado: Nível %d, Preço: %.2f", i, gridLevelsContraSell[i]);
            if(InpShowGridLines) UpdateGridLines();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Função para verificar novos timeframes (dia, semana, mês)        |
//+------------------------------------------------------------------+
void CheckNewTimeframes() {
   static int lastDay   = -1;
   static int lastWeek  = -1;
   static int lastMonth = -1;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   if(now.day != lastDay) {
      isNewDay = true;
      lastDay  = now.day;
      if(dailyLimitReached) {
         dailyLimitReached = false;
         Print("Novo dia: Limite diário resetado");
      }
   } else {
      isNewDay = false;
   }

   int currentWeekDay = now.day_of_week;
   if(lastWeek == -1) lastWeek = currentWeekDay;
   isNewWeek = (currentWeekDay < lastWeek);
   lastWeek  = currentWeekDay;

   if(now.mon != lastMonth) {
      isNewMonth = true;
      lastMonth  = now.mon;
   } else {
      isNewMonth = false;
   }
}

//+------------------------------------------------------------------+
//| Função para calcular o lucro diário                               |
//+------------------------------------------------------------------+
void CalculateDailyProfit() {
   if(isNewDay) dailyProfit = 0.0;

   double currentFloatingProfit = 0.0;
   MqlDateTime _now_ts;
   TimeToStruct(TimeCurrent(), _now_ts);
   _now_ts.hour = 0; _now_ts.min = 0; _now_ts.sec = 0;
   datetime todayStart = StructToTime(_now_ts);

   for(int i = 0; i < PositionsTotal(); i++) {
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            currentFloatingProfit += positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();
   }

   double realizedProfitToday = 0;
   if(HistorySelect(todayStart, TimeCurrent())) {
      for(int i = 0; i < HistoryDealsTotal(); i++) {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == InpMagicNumber &&
            HistoryDealGetString(dealTicket, DEAL_SYMBOL) == _Symbol &&
            (HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN ||
             HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT))
         {
            realizedProfitToday += HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                                   HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                                   HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
         }
      }
   }
   dailyProfit = realizedProfitToday + currentFloatingProfit;
}

void CalculateWeeklyProfit()
{
   double floating = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            floating += positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   MqlDateTime ws = now;
   ws.hour = 0; ws.min = 0; ws.sec = 0;
   ws.day -= now.day_of_week; // retrocede até domingo
   datetime weekStart = StructToTime(ws);

   double realized = 0;
   if(HistorySelect(weekStart, TimeCurrent()))
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  == InpMagicNumber &&
            HistoryDealGetString(ticket,  DEAL_SYMBOL) == _Symbol &&
            HistoryDealGetInteger(ticket, DEAL_ENTRY)  == DEAL_ENTRY_OUT)
            realized += HistoryDealGetDouble(ticket, DEAL_PROFIT)     +
                        HistoryDealGetDouble(ticket, DEAL_SWAP)       +
                        HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   weeklyProfit = realized + floating;
}

void CalculateMonthlyProfit()
{
   double floating = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            floating += positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   MqlDateTime ms = now;
   ms.day = 1; ms.hour = 0; ms.min = 0; ms.sec = 0;
   datetime monthStart = StructToTime(ms);

   double realized = 0;
   if(HistorySelect(monthStart, TimeCurrent()))
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  == InpMagicNumber &&
            HistoryDealGetString(ticket,  DEAL_SYMBOL) == _Symbol &&
            HistoryDealGetInteger(ticket, DEAL_ENTRY)  == DEAL_ENTRY_OUT)
            realized += HistoryDealGetDouble(ticket, DEAL_PROFIT)     +
                        HistoryDealGetDouble(ticket, DEAL_SWAP)       +
                        HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   monthlyProfit = realized + floating;
}

//+------------------------------------------------------------------+
//| Função para verificar os limites diários                          |
//+------------------------------------------------------------------+
bool CheckDailyLimits() {
   if(dailyLimitReached) return true;
   if(InpDailyLossLimit > 0 && dailyProfit <= -InpDailyLossLimit) {
      PrintFormat("Limite de loss diário (R$ %.2f) atingido! Lucro atual: R$ %.2f", InpDailyLossLimit, dailyProfit);
      CloseAllPositions();
      dailyLimitReached = true;
      return true;
   }
   if(InpDailyProfitLimit > 0 && dailyProfit >= InpDailyProfitLimit) {
      PrintFormat("Limite de gain diário (R$ %.2f) atingido! Lucro atual: R$ %.2f", InpDailyProfitLimit, dailyProfit);
      CloseAllPositions();
      dailyLimitReached = true;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Função para verificar o status do horário de operação             |
//+------------------------------------------------------------------+
ENUM_TIME_STATUS CheckTimeStatus() {
   if(InpSwingTradeMode) return TIME_ACTIVE;
   if(IsTimeEqual(InpCloseTime)) return TIME_CLOSE;
   if(IsTimeInRange(InpStartTime, InpEndTime)) return TIME_ACTIVE;
   return TIME_INACTIVE;
}

//+------------------------------------------------------------------+
//| Função para fechar todas as posições e ordens do robô             |
//+------------------------------------------------------------------+
void CloseAllPositions() {
   Print("Fechando todas as posições e cancelando ordens pendentes...");
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(orderInfo.SelectByIndex(i))
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber)
            if(!trade.OrderDelete(orderInfo.Ticket()))
               Print("Erro ao deletar ordem pendente: ", orderInfo.Ticket(), ", Erro: ", trade.ResultRetcode());
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            if(!trade.PositionClose(positionInfo.Ticket()))
               Print("Erro ao fechar posição: ", positionInfo.Ticket(), ", Erro: ", trade.ResultRetcode());
   }

   triggerPositionOpen    = false;
   triggerPositionTicket  = 0;
   triggerEntryPrice      = 0.0;

   gridAFavorOrderTicketBuy    = 0;
   gridAFavorOrderTicketSell   = 0;
   gridAFavorCurrentLevelBuy   = 0;
   gridAFavorCurrentLevelSell  = 0;
   gridAFavorActiveGridBuy     = false;
   gridAFavorActiveGridSell    = false;

   ArrayFill(gridLevelContraUsedBuy,  0, InpGridLevels, false);
   ArrayFill(gridLevelContraUsedSell, 0, InpGridLevels, false);
   ArrayFree(gridOrdersContraBuy);
   ArrayFree(gridOrdersContraSell);
   ArrayResize(gridOrdersContraBuy,  InpGridLevels);
   ArrayResize(gridOrdersContraSell, InpGridLevels);

   DeleteGridLines();
   gridInitialized = false;
   Print("Fechamento completo e reset de estado concluídos.");
}

//+------------------------------------------------------------------+
//| Função para gerenciar posições existentes                         |
//+------------------------------------------------------------------+
void ManagePositions() {
   double currentPrice = GetCurrentPrice();
   if(currentPrice <= 0) {
      PrintFormat("ERRO: Preço atual inválido (%.5f) em ManagePositions.", currentPrice);
      return;
   }

   bool gatilhoOriginalFound = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i)) {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber) {
            ulong currentTicket           = positionInfo.Ticket();
            ENUM_POSITION_TYPE posType    = positionInfo.PositionType();
            double posOpenPrice           = positionInfo.PriceOpen();
            double posTakeProfit          = positionInfo.TakeProfit();

            if(currentTicket == triggerPositionTicket) {
               gatilhoOriginalFound = true;

               if(InpTakeProfit > 0 && posTakeProfit > 0) {
                  bool tpAtingido = false;
                  if(posType == POSITION_TYPE_BUY  && currentPrice >= posTakeProfit) tpAtingido = true;
                  if(posType == POSITION_TYPE_SELL && currentPrice <= posTakeProfit) tpAtingido = true;

                  if(tpAtingido) {
                     PrintFormat("✅ Take Profit da ordem gatilho atingido! Fechando todas. TP: %.2f, Preço: %.2f",
                                 posTakeProfit, currentPrice);
                     CloseAllPositions();
                     return;
                  }
               }

               if(InpStopLoss > 0) {
                  if(posType == POSITION_TYPE_BUY  && currentPrice <= posOpenPrice - InpStopLoss * _Point) {
                     PrintFormat("Stop Loss GERAL atingido (BUY). Preço: %.2f, Gatilho: %.2f", currentPrice, posOpenPrice);
                     CloseAllPositions();
                     return;
                  }
                  if(posType == POSITION_TYPE_SELL && currentPrice >= posOpenPrice + InpStopLoss * _Point) {
                     PrintFormat("Stop Loss GERAL atingido (SELL). Preço: %.2f, Gatilho: %.2f", currentPrice, posOpenPrice);
                     CloseAllPositions();
                     return;
                  }
               }
            }
         }
      }
   }

   if(!gatilhoOriginalFound && triggerPositionOpen) {
      Print("Posição de gatilho ORIGINAL não encontrada. Resetando estado geral do robô.");
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Função para calcular SL/TP respeitando SYMBOL_TRADE_STOPS_LEVEL  |
//+------------------------------------------------------------------+
bool CalculateStopLevels(ENUM_POSITION_TYPE posType, double currentPrice,
                         double slPoints, double tpPoints,
                         double &stopLoss, double &takeProfit) {
   stopLoss   = 0;
   takeProfit = 0;

   if(currentPrice <= 0) {
      PrintFormat("ERRO: Preço atual inválido (%.5f). Não é possível calcular SL/TP.", currentPrice);
      return false;
   }
   if(slPoints <= 0 && tpPoints <= 0) return true;

   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLevel    = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stopLevel * point;

   double slDistance = slPoints * point;
   double tpDistance = tpPoints * point;

   if(slPoints > 0 && slDistance < minDistance) slDistance = minDistance + (10 * point);
   if(tpPoints > 0 && tpDistance < minDistance) tpDistance = minDistance + (10 * point);

   if(posType == POSITION_TYPE_BUY) {
      if(slPoints > 0) stopLoss   = NormalizeDouble(currentPrice - slDistance, _Digits);
      if(tpPoints > 0) takeProfit = NormalizeDouble(currentPrice + tpDistance, _Digits);
   } else {
      if(slPoints > 0) stopLoss   = NormalizeDouble(currentPrice + slDistance, _Digits);
      if(tpPoints > 0) takeProfit = NormalizeDouble(currentPrice - tpDistance, _Digits);
   }

   if(stopLoss > 0 && MathAbs(currentPrice - stopLoss) < minDistance) stopLoss = 0;
   if(takeProfit > 0 && MathAbs(currentPrice - takeProfit) < minDistance) takeProfit = 0;

   PrintFormat("SL/TP calculado -> Preço: %.2f, SL: %.2f, TP: %.2f", currentPrice, stopLoss, takeProfit);
   return true;
}

//+------------------------------------------------------------------+
//| Função para abrir posição gatilho                                 |
//+------------------------------------------------------------------+
void OpenTriggerPosition(ENUM_POSITION_TYPE posType) {
   if(triggerPositionOpen) {
      Print("Tentativa de abrir nova posição gatilho enquanto uma já está aberta. Ignorando.");
      return;
   }
   if(dailyLimitReached) {
      Print("Limite diário atingido. Bloqueando abertura de nova posição gatilho.");
      return;
   }

   string comment    = "GATILHO_" + EnumToString(InpTriggerType);
   bool result       = false;
   double stopLoss   = 0;
   double takeProfit = 0;
   double currentPrice = GetCurrentPrice();

   if(currentPrice <= 0) {
      PrintFormat("❌ ERRO CRÍTICO: Preço inválido para %s. Abortando abertura.", _Symbol);
      return;
   }

   if(!CalculateStopLevels(posType, currentPrice, InpStopLoss, InpTakeProfit, stopLoss, takeProfit)) {
      stopLoss = 0; takeProfit = 0;
   }

   if(posType == POSITION_TYPE_BUY)
      result = trade.Buy(InpLotgatilho, _Symbol, 0, stopLoss, takeProfit, comment);
   else
      result = trade.Sell(InpLotgatilho, _Symbol, 0, stopLoss, takeProfit, comment);

   if(result) {
      triggerPositionOpen   = true;
      triggerPositionType   = posType;
      triggerPositionTicket = trade.ResultOrder();
      triggerEntryPrice     = trade.ResultPrice();
      totalTrades++;
      PrintFormat("✅ Posição gatilho %s aberta: Ticket=%d, Preço=%.2f, SL=%.2f, TP=%.2f",
                  EnumToString(posType), triggerPositionTicket, triggerEntryPrice, stopLoss, takeProfit);
      gridInitialized = false;
   } else {
      PrintFormat("❌ Erro ao abrir posição gatilho %s: Erro=%d - %s",
                  EnumToString(posType), trade.ResultRetcode(), trade.ResultRetcodeDescription());

      if(trade.ResultRetcode() == 10016 || trade.ResultRetcode() == 10017) {
         Print("Tentando abrir posição sem SL/TP...");
         if(posType == POSITION_TYPE_BUY)
            result = trade.Buy(InpLotgatilho, _Symbol, 0, 0, 0, comment);
         else
            result = trade.Sell(InpLotgatilho, _Symbol, 0, 0, 0, comment);

         if(result) {
            triggerPositionOpen   = true;
            triggerPositionType   = posType;
            triggerPositionTicket = trade.ResultOrder();
            triggerEntryPrice     = trade.ResultPrice();
            totalTrades++;
            PrintFormat("⚠️ Posição gatilho %s aberta SEM proteção: Ticket=%d, Preço=%.2f",
                        EnumToString(posType), triggerPositionTicket, triggerEntryPrice);
            gridInitialized = false;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Função para inicializar o grid                                    |
//+------------------------------------------------------------------+
void InitializeGrid() {
   if(!triggerPositionOpen) return;
   PrintFormat("Inicializando/Reinicializando grid com referência: %.2f", triggerEntryPrice);

   if(triggerPositionType == POSITION_TYPE_BUY) {
      for(int i = 0; i < InpGridLevels; i++) {
         gridLevelsContraBuy[i]      = triggerEntryPrice - (i + 1) * InpGridInterval * _Point;
         gridLevelContraUsedBuy[i]   = false;
         gridOrdersContraBuy[i].isActive = false;
      }
      gridAFavorLastPriceBuy    = triggerEntryPrice;
      gridAFavorCurrentLevelBuy = 0;
      gridAFavorActiveGridBuy   = false;
      gridAFavorOrderTicketBuy  = 0;
   } else {
      for(int i = 0; i < InpGridLevels; i++) {
         gridLevelsContraSell[i]     = triggerEntryPrice + (i + 1) * InpGridInterval * _Point;
         gridLevelContraUsedSell[i]  = false;
         gridOrdersContraSell[i].isActive = false;
      }
      gridAFavorLastPriceSell    = triggerEntryPrice;
      gridAFavorCurrentLevelSell = 0;
      gridAFavorActiveGridSell   = false;
      gridAFavorOrderTicketSell  = 0;
   }

   if(InpShowGridLines) DrawGridLines();
   gridInitialized = true;
}

//+------------------------------------------------------------------+
//| Função para gerenciar o grid CONTRA                               |
//+------------------------------------------------------------------+
void ManageGrid() {
   if(!triggerPositionOpen) return;

   double currentPrice = GetCurrentPrice();
   if(currentPrice <= 0) {
      PrintFormat("ERRO: Preço inválido em ManageGrid.");
      return;
   }

   if(!gridInitialized) InitializeGrid();

   if(triggerPositionType == POSITION_TYPE_BUY) {
      for(int i = 0; i < InpGridLevels; i++) {
         if(currentPrice <= gridLevelsContraBuy[i] && !gridLevelContraUsedBuy[i]) {
            if(gridOrdersContraBuy[i].isActive) continue;
            string comment = "GRID_CONTRA_BUY_" + IntegerToString(i);
            double stopLoss = 0, takeProfit = 0;
            double tpPoints = InpGridInterval;
            double slPoints = InpStopLoss;
            if(positionInfo.SelectByTicket(triggerPositionTicket) && positionInfo.StopLoss() > 0)
               slPoints = MathAbs(currentPrice - positionInfo.StopLoss()) / _Point;

            if(CalculateStopLevels(POSITION_TYPE_BUY, currentPrice, slPoints, tpPoints, stopLoss, takeProfit)) {
               if(trade.Buy(InpLotSize, _Symbol, 0, stopLoss, takeProfit, comment)) {
                  ulong ticket = trade.ResultOrder();
                  PrintFormat("✅ Grid Contra BUY_%d aberto: Ticket=%d, Preço=%.2f, SL=%.2f, TP=%.2f",
                              i, ticket, trade.ResultPrice(), stopLoss, takeProfit);
                  gridLevelContraUsedBuy[i]          = true;
                  gridOrdersContraBuy[i].ticket      = ticket;
                  gridOrdersContraBuy[i].price       = trade.ResultPrice();
                  gridOrdersContraBuy[i].takeProfit  = takeProfit;
                  gridOrdersContraBuy[i].comment     = comment;
                  gridOrdersContraBuy[i].isActive    = true;
                  if(InpShowGridLines) UpdateGridLines();
               } else {
                  PrintFormat("❌ Erro Grid Contra BUY_%d: %d - %s", i, trade.ResultRetcode(), trade.ResultRetcodeDescription());
                  if(trade.ResultRetcode() == 10016 || trade.ResultRetcode() == 10017) {
                     if(trade.Buy(InpLotSize, _Symbol, 0, 0, 0, comment)) {
                        ulong ticket = trade.ResultOrder();
                        gridLevelContraUsedBuy[i]       = true;
                        gridOrdersContraBuy[i].ticket   = ticket;
                        gridOrdersContraBuy[i].price    = trade.ResultPrice();
                        gridOrdersContraBuy[i].takeProfit = 0;
                        gridOrdersContraBuy[i].comment  = comment;
                        gridOrdersContraBuy[i].isActive = true;
                        if(InpShowGridLines) UpdateGridLines();
                     }
                  }
               }
            }
         }
      }
   } else {
      for(int i = 0; i < InpGridLevels; i++) {
         if(currentPrice >= gridLevelsContraSell[i] && !gridLevelContraUsedSell[i]) {
            if(gridOrdersContraSell[i].isActive) continue;
            string comment = "GRID_CONTRA_SELL_" + IntegerToString(i);
            double stopLoss = 0, takeProfit = 0;
            double tpPoints = InpGridInterval;
            double slPoints = InpStopLoss;
            if(positionInfo.SelectByTicket(triggerPositionTicket) && positionInfo.StopLoss() > 0)
               slPoints = MathAbs(currentPrice - positionInfo.StopLoss()) / _Point;

            if(CalculateStopLevels(POSITION_TYPE_SELL, currentPrice, slPoints, tpPoints, stopLoss, takeProfit)) {
               if(trade.Sell(InpLotSize, _Symbol, 0, stopLoss, takeProfit, comment)) {
                  ulong ticket = trade.ResultOrder();
                  PrintFormat("✅ Grid Contra SELL_%d aberto: Ticket=%d, Preço=%.2f, SL=%.2f, TP=%.2f",
                              i, ticket, trade.ResultPrice(), stopLoss, takeProfit);
                  gridLevelContraUsedSell[i]         = true;
                  gridOrdersContraSell[i].ticket     = ticket;
                  gridOrdersContraSell[i].price      = trade.ResultPrice();
                  gridOrdersContraSell[i].takeProfit = takeProfit;
                  gridOrdersContraSell[i].comment    = comment;
                  gridOrdersContraSell[i].isActive   = true;
                  if(InpShowGridLines) UpdateGridLines();
               } else {
                  PrintFormat("❌ Erro Grid Contra SELL_%d: %d - %s", i, trade.ResultRetcode(), trade.ResultRetcodeDescription());
                  if(trade.ResultRetcode() == 10016 || trade.ResultRetcode() == 10017) {
                     if(trade.Sell(InpLotSize, _Symbol, 0, 0, 0, comment)) {
                        ulong ticket = trade.ResultOrder();
                        gridLevelContraUsedSell[i]      = true;
                        gridOrdersContraSell[i].ticket  = ticket;
                        gridOrdersContraSell[i].price   = trade.ResultPrice();
                        gridOrdersContraSell[i].takeProfit = 0;
                        gridOrdersContraSell[i].comment = comment;
                        gridOrdersContraSell[i].isActive = true;
                        if(InpShowGridLines) UpdateGridLines();
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Função para atualizar ordem limite A FAVOR                        |
//+------------------------------------------------------------------+
void UpdateAFavorLimitOrder() {
   if(!triggerPositionOpen || InpGridType != GRID_DYNAMIC) return;

   double currentPrice = GetCurrentPrice();
   if(currentPrice <= 0) {
      PrintFormat("ERRO: Preço inválido em UpdateAFavorLimitOrder.");
      return;
   }

   double point    = _Point;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double triggerStopLoss = 0;
   if(positionInfo.SelectByTicket(triggerPositionTicket))
      triggerStopLoss = positionInfo.StopLoss();

   if(triggerPositionType == POSITION_TYPE_BUY) {
      double nextPotentialLevel = gridAFavorLastPriceBuy + InpGridInterval * point;
      if(currentPrice > nextPotentialLevel) {
         double newLimitLevel = NormalizeDouble(currentPrice - InpGridInterval * point, _Digits);
         if(newLimitLevel >= currentPrice - tickSize)
            newLimitLevel = NormalizeDouble(currentPrice - tickSize, _Digits);

         if(gridAFavorOrderTicketBuy > 0) {
            if(!trade.OrderDelete(gridAFavorOrderTicketBuy))
               Print("Erro ao deletar ordem a favor (BUY) antiga: ", gridAFavorOrderTicketBuy);
            gridAFavorOrderTicketBuy = 0;
         }

         double takeProfit = NormalizeDouble(newLimitLevel + InpGridInterval * _Point, _Digits);
         string comment    = "GRID_AFAVOR_BUY_LIMIT";
         if(trade.BuyLimit(InpLotSize, newLimitLevel, _Symbol, triggerStopLoss, takeProfit, ORDER_TIME_GTC, 0, comment)) {
            gridAFavorOrderTicketBuy    = trade.ResultOrder();
            gridAFavorCurrentLevelBuy  = newLimitLevel;
            gridAFavorActiveGridBuy    = true;
            gridAFavorLastPriceBuy     = currentPrice;
            PrintFormat("Ordem Limite A Favor (BUY) colocada: Ticket=%d, Preço=%.2f, SL=%.2f, TP=%.2f",
                        gridAFavorOrderTicketBuy, newLimitLevel, triggerStopLoss, takeProfit);
            if(InpShowGridLines) UpdateGridLines();
         } else {
            PrintFormat("Erro ao colocar ordem limite a favor (BUY): %.2f, Erro: %d - %s",
                        newLimitLevel, trade.ResultRetcode(), trade.ResultRetcodeDescription());
            gridAFavorActiveGridBuy = false;
         }
      }

      if(gridAFavorActiveGridBuy) {
         bool orderExists = false;
         for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(orderInfo.SelectByIndex(i))
               if(orderInfo.Ticket() == gridAFavorOrderTicketBuy && orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber) {
                  orderExists = true; break;
               }
         }
         if(!orderExists) {
            Print("Ordem limite a favor (BUY) executada! Nível: ", gridAFavorCurrentLevelBuy);
            double newReferencePrice    = gridAFavorCurrentLevelBuy;
            ulong  executedPositionTicket = 0;

            for(int i = PositionsTotal() - 1; i >= 0; i--) {
               if(positionInfo.SelectByIndex(i)) {
                  if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber &&
                     positionInfo.PositionType() == POSITION_TYPE_BUY)
                  {
                     double posOpenPrice = positionInfo.PriceOpen();
                     if(MathAbs(posOpenPrice - gridAFavorCurrentLevelBuy) < tickSize * 10 &&
                        TimeCurrent() - positionInfo.Time() < 30)
                     {
                        newReferencePrice       = posOpenPrice;
                        executedPositionTicket  = positionInfo.Ticket();
                        PrintFormat("✅ Posição A Favor (BUY) identificada: Ticket=%d, Preço=%.2f, TP=%.2f",
                                    executedPositionTicket, newReferencePrice, positionInfo.TakeProfit());
                        break;
                     }
                  }
               }
            }

            if(executedPositionTicket == 0) {
               Print("⚠️ AVISO: Posição a favor não identificada. Resetando controle sem reset do grid.");
               gridAFavorOrderTicketBuy   = 0;
               gridAFavorCurrentLevelBuy  = 0;
               gridAFavorActiveGridBuy    = false;
               return;
            }

            ResetGridOrders(executedPositionTicket);
            triggerEntryPrice          = newReferencePrice;
            gridInitialized            = false;
            gridAFavorOrderTicketBuy   = 0;
            gridAFavorCurrentLevelBuy  = 0;
            gridAFavorActiveGridBuy    = false;
            gridAFavorLastPriceBuy     = newReferencePrice;
            PrintFormat("Grid resetado. Nova referência: %.2f", newReferencePrice);
         }
      }
   } else {
      double nextPotentialLevel = gridAFavorLastPriceSell - InpGridInterval * point;
      if(currentPrice < nextPotentialLevel) {
         double newLimitLevel = NormalizeDouble(currentPrice + InpGridInterval * point, _Digits);
         if(newLimitLevel <= currentPrice + tickSize)
            newLimitLevel = NormalizeDouble(currentPrice + tickSize, _Digits);

         if(gridAFavorOrderTicketSell > 0) {
            if(!trade.OrderDelete(gridAFavorOrderTicketSell))
               Print("Erro ao deletar ordem a favor (SELL) antiga: ", gridAFavorOrderTicketSell);
            gridAFavorOrderTicketSell = 0;
         }

         double takeProfit = NormalizeDouble(newLimitLevel - InpGridInterval * _Point, _Digits);
         string comment    = "GRID_AFAVOR_SELL_LIMIT";
         if(trade.SellLimit(InpLotSize, newLimitLevel, _Symbol, triggerStopLoss, takeProfit, ORDER_TIME_GTC, 0, comment)) {
            gridAFavorOrderTicketSell   = trade.ResultOrder();
            gridAFavorCurrentLevelSell  = newLimitLevel;
            gridAFavorActiveGridSell    = true;
            gridAFavorLastPriceSell     = currentPrice;
            PrintFormat("Ordem Limite A Favor (SELL) colocada: Ticket=%d, Preço=%.2f, SL=%.2f, TP=%.2f",
                        gridAFavorOrderTicketSell, newLimitLevel, triggerStopLoss, takeProfit);
            if(InpShowGridLines) UpdateGridLines();
         } else {
            PrintFormat("Erro ao colocar ordem limite a favor (SELL): %.2f, Erro: %d - %s",
                        newLimitLevel, trade.ResultRetcode(), trade.ResultRetcodeDescription());
            gridAFavorActiveGridSell = false;
         }
      }

      if(gridAFavorActiveGridSell) {
         bool orderExists = false;
         for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(orderInfo.SelectByIndex(i))
               if(orderInfo.Ticket() == gridAFavorOrderTicketSell && orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber) {
                  orderExists = true; break;
               }
         }
         if(!orderExists) {
            Print("Ordem limite a favor (SELL) executada! Nível: ", gridAFavorCurrentLevelSell);
            double newReferencePrice      = gridAFavorCurrentLevelSell;
            ulong  executedPositionTicket = 0;

            for(int i = PositionsTotal() - 1; i >= 0; i--) {
               if(positionInfo.SelectByIndex(i)) {
                  if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber &&
                     positionInfo.PositionType() == POSITION_TYPE_SELL)
                  {
                     double posOpenPrice = positionInfo.PriceOpen();
                     if(MathAbs(posOpenPrice - gridAFavorCurrentLevelSell) < tickSize * 10 &&
                        TimeCurrent() - positionInfo.Time() < 30)
                     {
                        newReferencePrice      = posOpenPrice;
                        executedPositionTicket = positionInfo.Ticket();
                        PrintFormat("✅ Posição A Favor (SELL) identificada: Ticket=%d, Preço=%.2f, TP=%.2f",
                                    executedPositionTicket, newReferencePrice, positionInfo.TakeProfit());
                        break;
                     }
                  }
               }
            }

            if(executedPositionTicket == 0) {
               Print("⚠️ AVISO: Posição a favor SELL não identificada. Resetando controle.");
               gridAFavorOrderTicketSell  = 0;
               gridAFavorCurrentLevelSell = 0;
               gridAFavorActiveGridSell   = false;
               return;
            }

            ResetGridOrders(executedPositionTicket);
            triggerEntryPrice          = newReferencePrice;
            gridInitialized            = false;
            gridAFavorOrderTicketSell  = 0;
            gridAFavorCurrentLevelSell = 0;
            gridAFavorActiveGridSell   = false;
            gridAFavorLastPriceSell    = newReferencePrice;
            PrintFormat("Grid resetado. Nova referência: %.2f", newReferencePrice);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Função para resetar grid preservando posição a favor             |
//+------------------------------------------------------------------+
void ResetGridOrders(ulong preservePositionTicket = 0) {
   Print("Resetando grid (exceto gatilho original e posição preservada)...");

   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(orderInfo.SelectByIndex(i)) {
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber) {
            string comment = orderInfo.Comment();
            if(StringFind(comment, "GRID_AFAVOR_") >= 0 || StringFind(comment, "GRID_CONTRA_") >= 0)
               if(!trade.OrderDelete(orderInfo.Ticket()))
                  Print("Erro ao deletar ordem do grid: ", orderInfo.Ticket());
         }
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i)) {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber) {
            ulong currentTicket = positionInfo.Ticket();
            if(currentTicket == triggerPositionTicket) continue;
            if(preservePositionTicket > 0 && currentTicket == preservePositionTicket) {
               PrintFormat("Preservando posição a favor: Ticket=%d, Preço=%.2f, TP=%.2f",
                           currentTicket, positionInfo.PriceOpen(), positionInfo.TakeProfit());
               continue;
            }
            string comment = positionInfo.Comment();
            if(StringFind(comment, "GRID_AFAVOR_") >= 0 || StringFind(comment, "GRID_CONTRA_") >= 0)
               if(!trade.PositionClose(currentTicket))
                  Print("Erro ao fechar posição do grid: ", currentTicket);
         }
      }
   }

   ArrayFill(gridLevelContraUsedBuy,  0, InpGridLevels, false);
   ArrayFill(gridLevelContraUsedSell, 0, InpGridLevels, false);
   ArrayFree(gridOrdersContraBuy);
   ArrayFree(gridOrdersContraSell);
   ArrayResize(gridOrdersContraBuy,  InpGridLevels);
   ArrayResize(gridOrdersContraSell, InpGridLevels);

   gridAFavorOrderTicketBuy   = 0;
   gridAFavorOrderTicketSell  = 0;
   gridAFavorCurrentLevelBuy  = 0;
   gridAFavorCurrentLevelSell = 0;
   gridAFavorActiveGridBuy    = false;
   gridAFavorActiveGridSell   = false;

   DeleteGridLines(false);
   Print("Reset do grid concluído. Posição preservada: ", preservePositionTicket);
}

//+------------------------------------------------------------------+
//| Função para desenhar as linhas do grid                            |
//+------------------------------------------------------------------+
void DrawGridLines() {
   if(!triggerPositionOpen) return;
   DeleteGridLines(true);

   color gridLineColor  = clrDarkGray;
   color usedLineColor  = clrRed;
   color favorLineColor = clrGreen;
   color refLineColor   = (triggerPositionType == POSITION_TYPE_BUY) ? clrBlue : clrRed;

   string refLineName = "GridReferenciaAtual";
   ObjectCreate(0, refLineName, OBJ_HLINE, 0, 0, triggerEntryPrice);
   ObjectSetInteger(0, refLineName, OBJPROP_COLOR, refLineColor);
   ObjectSetInteger(0, refLineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, refLineName, OBJPROP_WIDTH, 2);
   ObjectSetString(0, refLineName, OBJPROP_TEXT, "Ref Grid: " + DoubleToString(triggerEntryPrice, _Digits));
   ObjectSetInteger(0, refLineName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, refLineName, OBJPROP_BACK, true);

   if(triggerPositionType == POSITION_TYPE_BUY) {
      for(int i = 0; i < InpGridLevels; i++) {
         string lineName = "GridContraBuy" + IntegerToString(i);
         ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, gridLevelsContraBuy[i]);
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, gridLevelContraUsedBuy[i] ? usedLineColor : gridLineColor);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
         ObjectSetString(0, lineName, OBJPROP_TEXT, "Contra Buy " + IntegerToString(i+1));
         ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
      }
      if(InpGridType == GRID_DYNAMIC && gridAFavorOrderTicketBuy > 0) {
         string favorLineName = "GridAFavorBuyLimit";
         ObjectCreate(0, favorLineName, OBJ_HLINE, 0, 0, gridAFavorCurrentLevelBuy);
         ObjectSetInteger(0, favorLineName, OBJPROP_COLOR, favorLineColor);
         ObjectSetInteger(0, favorLineName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, favorLineName, OBJPROP_WIDTH, 1);
         ObjectSetString(0, favorLineName, OBJPROP_TEXT, "A Favor Buy: " + DoubleToString(gridAFavorCurrentLevelBuy, _Digits));
         ObjectSetInteger(0, favorLineName, OBJPROP_SELECTABLE, false);
      }
   } else {
      for(int i = 0; i < InpGridLevels; i++) {
         string lineName = "GridContraSell" + IntegerToString(i);
         ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, gridLevelsContraSell[i]);
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, gridLevelContraUsedSell[i] ? usedLineColor : gridLineColor);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
         ObjectSetString(0, lineName, OBJPROP_TEXT, "Contra Sell " + IntegerToString(i+1));
         ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
      }
      if(InpGridType == GRID_DYNAMIC && gridAFavorOrderTicketSell > 0) {
         string favorLineName = "GridAFavorSellLimit";
         ObjectCreate(0, favorLineName, OBJ_HLINE, 0, 0, gridAFavorCurrentLevelSell);
         ObjectSetInteger(0, favorLineName, OBJPROP_COLOR, favorLineColor);
         ObjectSetInteger(0, favorLineName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, favorLineName, OBJPROP_WIDTH, 1);
         ObjectSetString(0, favorLineName, OBJPROP_TEXT, "A Favor Sell: " + DoubleToString(gridAFavorCurrentLevelSell, _Digits));
         ObjectSetInteger(0, favorLineName, OBJPROP_SELECTABLE, false);
      }
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Função para atualizar as linhas do grid                           |
//+------------------------------------------------------------------+
void UpdateGridLines() {
   if(!InpShowGridLines || !triggerPositionOpen) return;

   color gridLineColor  = clrDarkGray;
   color usedLineColor  = clrRed;
   color favorLineColor = clrGreen;

   if(triggerPositionType == POSITION_TYPE_BUY) {
      for(int i = 0; i < InpGridLevels; i++) {
         string lineName = "GridContraBuy" + IntegerToString(i);
         if(ObjectFind(0, lineName) >= 0)
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, gridLevelContraUsedBuy[i] ? usedLineColor : gridLineColor);
      }
      if(InpGridType == GRID_DYNAMIC) {
         ObjectDelete(0, "GridAFavorBuyLimit");
         if(gridAFavorOrderTicketBuy > 0) {
            ObjectCreate(0, "GridAFavorBuyLimit", OBJ_HLINE, 0, 0, gridAFavorCurrentLevelBuy);
            ObjectSetInteger(0, "GridAFavorBuyLimit", OBJPROP_COLOR, favorLineColor);
            ObjectSetInteger(0, "GridAFavorBuyLimit", OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(0, "GridAFavorBuyLimit", OBJPROP_WIDTH, 1);
            ObjectSetString(0, "GridAFavorBuyLimit", OBJPROP_TEXT, "A Favor Buy: " + DoubleToString(gridAFavorCurrentLevelBuy, _Digits));
            ObjectSetInteger(0, "GridAFavorBuyLimit", OBJPROP_SELECTABLE, false);
         }
      }
   } else {
      for(int i = 0; i < InpGridLevels; i++) {
         string lineName = "GridContraSell" + IntegerToString(i);
         if(ObjectFind(0, lineName) >= 0)
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, gridLevelContraUsedSell[i] ? usedLineColor : gridLineColor);
      }
      if(InpGridType == GRID_DYNAMIC) {
         ObjectDelete(0, "GridAFavorSellLimit");
         if(gridAFavorOrderTicketSell > 0) {
            ObjectCreate(0, "GridAFavorSellLimit", OBJ_HLINE, 0, 0, gridAFavorCurrentLevelSell);
            ObjectSetInteger(0, "GridAFavorSellLimit", OBJPROP_COLOR, favorLineColor);
            ObjectSetInteger(0, "GridAFavorSellLimit", OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(0, "GridAFavorSellLimit", OBJPROP_WIDTH, 1);
            ObjectSetString(0, "GridAFavorSellLimit", OBJPROP_TEXT, "A Favor Sell: " + DoubleToString(gridAFavorCurrentLevelSell, _Digits));
            ObjectSetInteger(0, "GridAFavorSellLimit", OBJPROP_SELECTABLE, false);
         }
      }
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Função para remover as linhas do grid                             |
//+------------------------------------------------------------------+
void DeleteGridLines(bool deleteReference = true) {
   ObjectsDeleteAll(0, "GridContraBuy");
   ObjectsDeleteAll(0, "GridContraSell");
   ObjectDelete(0, "GridAFavorBuyLimit");
   ObjectDelete(0, "GridAFavorSellLimit");
   if(deleteReference) ObjectDelete(0, "GridReferenciaAtual");
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Função para verificar gatilhos                                    |
//+------------------------------------------------------------------+
void CheckTriggers() {
   CheckStatsTrigger();
}

//+------------------------------------------------------------------+
//| FUNÇÃO CORRIGIDA: Verificar gatilho por percentual               |
//| CORREÇÃO PRINCIPAL: Comparação int vs string substituída por     |
//| comparação int vs int (g_currentTime >= g_startTimeHHMM)        |
//+------------------------------------------------------------------+
void CheckStatsTrigger() {

   // *** VALIDAÇÃO: Garantir que os preços estão calculados ***
   if(g_precoEntradaV <= 0 || g_precoEntradaC <= 0 || g_aberturaDia <= 0) {
      PrintFormat("TRIGGER: Preços não disponíveis ainda. abertura=%.2f, entradaC=%.2f, entradaV=%.2f",
                  g_aberturaDia, g_precoEntradaC, g_precoEntradaV);
      return;
   }

   // *** VALIDAÇÃO: Verificar se o candle de referência tem dados ***
   if(g_fechamentoBarra <= 0) {
      Print("TRIGGER: Fechamento da barra ainda não disponível.");
      return;
   }

   // *** CORREÇÃO PRINCIPAL: Comparar int com int ***
   // g_currentTime é int HHMM (ex: 930)
   // g_startTimeHHMM é int HHMM calculado de InpStartTime (ex: 900)
   // ANTES (ERRADO): g_currentTime > InpStartTime  (int vs string -> sempre false!)
   // DEPOIS (CERTO):  g_currentTime >= g_startTimeHHMM

   PrintFormat("TRIGGER CHECK: hora=%d >= inicio=%d | fechaBarra=%.2f | entradaV=%.2f | entradaC=%.2f",
               g_currentTime, g_startTimeHHMM, g_fechamentoBarra, g_precoEntradaV, g_precoEntradaC);

   // Gatilho de VENDA: fechamento da barra abaixo do preço de entrada de venda
   if(g_currentTime >= g_startTimeHHMM && g_fechamentoBarra < g_precoEntradaV) {
      PrintFormat("🔴 TRIGGER VENDA acionado! Barra (%.2f) < EntradaV (%.2f)",
                  g_fechamentoBarra, g_precoEntradaV);
      OpenTriggerPosition(tendencia ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);
      return; // Evitar duplo trigger no mesmo tick
   }

   // Gatilho de COMPRA: fechamento da barra acima do preço de entrada de compra
   if(g_currentTime >= g_startTimeHHMM && g_fechamentoBarra > g_precoEntradaC) {
      PrintFormat("🟢 TRIGGER COMPRA acionado! Barra (%.2f) > EntradaC (%.2f)",
                  g_fechamentoBarra, g_precoEntradaC);
      OpenTriggerPosition(tendencia ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
   }
}


//+------------------------------------------------------------------+
//| PAINEL PREMIUM — mesmo conceito do STATS                         |
//+------------------------------------------------------------------+
void CriarPainel()
{
   // PAINEL PRINCIPAL
   ObjectCreate(0, PANEL_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_YDISTANCE, 50);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_XSIZE, PANEL_WIDTH);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_YSIZE, PANEL_HEADER_HEIGHT + PANEL_BODY_HEIGHT);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_FILL, true);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_BGCOLOR, C'18,22,35');
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_BORDER_COLOR, C'45,50,70');
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_SELECTABLE, false);

   // HEADER
   ObjectCreate(0, PANEL_HEADER_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_YDISTANCE, 50);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_XSIZE, PANEL_WIDTH);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_YSIZE, PANEL_HEADER_HEIGHT);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_FILL, true);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_BGCOLOR, C'8,12,22');
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_BORDER_COLOR, C'28,34,55');

   // LOGO
   ObjectCreate(0, "SLYBOT_LOGO", OBJ_BITMAP_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_XDISTANCE, 15);
   ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_YDISTANCE, 55);
   ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_FILL, false);
   ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_BGCOLOR, clrNONE);
   ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_COLOR, clrNONE);
   ObjectSetString(0, "SLYBOT_LOGO", OBJPROP_BMPFILE, "::Images\\slybot_final.bmp");

   // Título
   ObjectCreate(0, "LBL_TITLE", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LBL_TITLE", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "LBL_TITLE", OBJPROP_XDISTANCE, 150);
   ObjectSetInteger(0, "LBL_TITLE", OBJPROP_YDISTANCE, 60);
   ObjectSetInteger(0, "LBL_TITLE", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "LBL_TITLE", OBJPROP_FONTSIZE, 13);
   ObjectSetString(0, "LBL_TITLE", OBJPROP_TEXT, "GRIID v1.53");

   // Resultado no header (colapsado)
   ObjectCreate(0, "LBL_RESULTADO_DIA", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_XDISTANCE, 220);
   ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_YDISTANCE, 62);
   ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, "LBL_RESULTADO_DIA", OBJPROP_TEXT, "");

   // BOTÃO COLLAPSE
   ObjectCreate(0, BTN_COLLAPSE, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_XDISTANCE, PANEL_WIDTH - 25);
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_YDISTANCE, 60);
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_FONTSIZE, 12);
   ObjectSetString(0, BTN_COLLAPSE, OBJPROP_TEXT, "▼");
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_SELECTABLE, true);

   // BOTÃO POWER
   ObjectCreate(0, "BTN_POWER_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_XDISTANCE, PANEL_WIDTH - 80);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_YDISTANCE, 60);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_XSIZE, 40);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_YSIZE, 20);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_FILL, true);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_BGCOLOR, clrLime);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_BORDER_COLOR, clrLime);
   ObjectCreate(0, "BTN_POWER_TXT", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "BTN_POWER_TXT", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "BTN_POWER_TXT", OBJPROP_XDISTANCE, PANEL_WIDTH - 77);
   ObjectSetInteger(0, "BTN_POWER_TXT", OBJPROP_YDISTANCE, 62);
   ObjectSetInteger(0, "BTN_POWER_TXT", OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, "BTN_POWER_TXT", OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, "BTN_POWER_TXT", OBJPROP_TEXT, "ON");

   // BODY
   ObjectCreate(0, PANEL_BODY_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_YDISTANCE, 50 + PANEL_HEADER_HEIGHT);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_XSIZE, PANEL_WIDTH);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_YSIZE, PANEL_BODY_HEIGHT);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_FILL, true);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_BGCOLOR, C'20,26,45');

   // LINHAS DO BODY
   int baseY = 50 + PANEL_HEADER_HEIGHT + 15;
   lineY = baseY;
   lineHeight = 16;

   CriarLinhaBody("LBL_NOME_ESTRATEGIA", "---", 25);
   CriarLinhaBody("LBL_PLANO",   "Plano: ---",  25);
   CriarLinhaBody("LBL_STATUS",  "Status: ---", 25);
   CriarLinhaBody("LBL_EXPIRA",  "Expira: ---", 25);
   lineY += 8;
   CriarLinhaBody("LBL_ATIVO",   "Ativo: ---",  25);
   CriarLinhaBody("LBL_GRID",    "Grid: ---",   25);
   lineY += 8;
   CriarLinhaBody("LBL_STATUS_OP", "Op: ---",   25);
   CriarLinhaBody("LBL_HORA",    "Hora: ---",   25);

   // CARDS
   int cardY      = lineY + 10;
   int margem     = 15;
   int espaco     = 6;
   int larguraCard = (PANEL_WIDTH - (margem * 2) - (espaco * 3)) / 4;
   int alturaCard  = 42;

   CriarCard("CARD_ABERTO_BG", "CARD_ABERTO_TIT", "CARD_ABERTO_VAL", "ABERTO",
             margem, cardY, larguraCard, alturaCard);
   CriarCard("CARD_DIA_BG", "CARD_DIA_TIT", "CARD_DIA_VAL", "DIA",
             margem + larguraCard + espaco, cardY, larguraCard, alturaCard);
   CriarCard("CARD_SEMANA_BG", "CARD_SEMANA_TIT", "CARD_SEMANA_VAL", "SEMANA",
             margem + (larguraCard * 2) + (espaco * 2), cardY, larguraCard, alturaCard);
   CriarCard("CARD_MES_BG", "CARD_MES_TIT", "CARD_MES_VAL", "MÊS",
             margem + (larguraCard * 3) + (espaco * 3), cardY, larguraCard, alturaCard);

   // BOTÃO FECHAR TUDO
   ObjectCreate(0, "BTN_CLOSE_ALL_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_YDISTANCE, cardY + alturaCard + 15);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_XSIZE, PANEL_WIDTH - 40);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_YSIZE, 28);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_FILL, true);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_BGCOLOR, C'150,20,20');
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_BORDER_COLOR, C'150,20,20');
   ObjectCreate(0, "BTN_CLOSE_ALL_TXT", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_XDISTANCE, PANEL_WIDTH / 2);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_YDISTANCE, cardY + alturaCard + 29);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, "BTN_CLOSE_ALL_TXT", OBJPROP_TEXT, "PARAR E FECHAR");

   int alturaFinal = cardY + alturaCard + 70;
   ObjectSetInteger(0, PANEL_NAME,      OBJPROP_YSIZE, alturaFinal);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_YSIZE, alturaFinal - PANEL_HEADER_HEIGHT);

   // Z-ORDER
   ObjectSetInteger(0, PANEL_NAME,       OBJPROP_ZORDER, 0);
   ObjectSetInteger(0, PANEL_BODY_NAME,  OBJPROP_ZORDER, 1);
   ObjectSetInteger(0, PANEL_HEADER_NAME,OBJPROP_ZORDER, 2);
   ObjectSetInteger(0, "SLYBOT_LOGO",    OBJPROP_ZORDER, 3);
   ObjectSetInteger(0, "LBL_TITLE",      OBJPROP_ZORDER, 3);
   ObjectSetInteger(0, BTN_COLLAPSE,     OBJPROP_ZORDER, 5);
   ObjectSetInteger(0, "BTN_POWER_BG",   OBJPROP_ZORDER, 6);
   ObjectSetInteger(0, "BTN_POWER_TXT",  OBJPROP_ZORDER, 7);

   // BACK = false → painel na frente dos elementos do gráfico
   ObjectSetInteger(0, PANEL_NAME,         OBJPROP_BACK, false);
   ObjectSetInteger(0, PANEL_HEADER_NAME,  OBJPROP_BACK, false);
   ObjectSetInteger(0, PANEL_BODY_NAME,    OBJPROP_BACK, false);
   ObjectSetInteger(0, "SLYBOT_LOGO",      OBJPROP_BACK, false);
   ObjectSetInteger(0, "LBL_TITLE",        OBJPROP_BACK, false);
   ObjectSetInteger(0, BTN_COLLAPSE,       OBJPROP_BACK, false);
   ObjectSetInteger(0, "BTN_POWER_BG",     OBJPROP_BACK, false);
   ObjectSetInteger(0, "BTN_POWER_TXT",    OBJPROP_BACK, false);
   ObjectSetInteger(0, "LBL_RESULTADO_DIA",OBJPROP_BACK, false);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_BACK, false);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT",OBJPROP_BACK, false);

   ChartRedraw();
}

void CriarLabelBody(string nome, string texto, int x, int y, color cor, int tamanho = 10)
{
   ObjectCreate(0, nome, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nome, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, tamanho);
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
}

void CriarLinhaBody(string nome, string texto, int x)
{
   CriarLabelBody(nome, texto, x, lineY, clrWhite, 9);
   lineY += lineHeight;
}

void CriarCard(string nomeBg, string nomeTitulo, string nomeValor,
               string titulo, int x, int y, int largura, int altura)
{
   ObjectCreate(0, nomeBg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nomeBg, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, nomeBg, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nomeBg, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nomeBg, OBJPROP_XSIZE, largura);
   ObjectSetInteger(0, nomeBg, OBJPROP_YSIZE, altura);
   ObjectSetInteger(0, nomeBg, OBJPROP_FILL, true);
   ObjectSetInteger(0, nomeBg, OBJPROP_BGCOLOR, C'35,45,75');
   ObjectSetInteger(0, nomeBg, OBJPROP_BORDER_COLOR, C'35,45,75');
   ObjectSetInteger(0, nomeBg, OBJPROP_BORDER_TYPE, BORDER_FLAT);

   ObjectCreate(0, nomeTitulo, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_XDISTANCE, x + largura / 2);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_YDISTANCE, y + 10);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, nomeTitulo, OBJPROP_TEXT, titulo);

   ObjectCreate(0, nomeValor, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nomeValor, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, nomeValor, OBJPROP_XDISTANCE, x + largura / 2);
   ObjectSetInteger(0, nomeValor, OBJPROP_YDISTANCE, (int)(y + altura * 0.62));
   ObjectSetInteger(0, nomeValor, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, nomeValor, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, nomeValor, OBJPROP_FONTSIZE, 11);
   ObjectSetString(0, nomeValor, OBJPROP_TEXT, "0.00");
}

void AtualizarPainel(ENUM_TIME_STATUS timeStatus)
{
   if(ObjectFind(0, "LBL_PLANO") < 0) return;

   // Flutuante
   double aberto = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            aberto += positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();

   // Resultado no header colapsado
   if(g_panelCollapsed)
   {
      string txt = "Hoje: " + DoubleToString(dailyProfit, 2);
      ObjectSetString(0, "LBL_RESULTADO_DIA", OBJPROP_TEXT, txt);
      ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_COLOR, dailyProfit >= 0 ? clrLime : clrTomato);
   }
   else
      ObjectSetString(0, "LBL_RESULTADO_DIA", OBJPROP_TEXT, "");

   // Status da operação
   string statusOp;
   if(dailyLimitReached)
      statusOp = "LIMITE DIÁRIO";
   else if(!InpSwingTradeMode && timeStatus == TIME_CLOSE)
      statusOp = "FECHAMENTO";
   else if(!InpSwingTradeMode && timeStatus == TIME_INACTIVE)
      statusOp = "FORA HORÁRIO";
   else if(triggerPositionOpen)
      statusOp = (triggerPositionType == POSITION_TYPE_BUY) ? "COMPRADO" : "VENDIDO";
   else
      statusOp = "Aguardando";

   string gridStatus = triggerPositionOpen
      ? ((InpGridType == GRID_FIXED) ? "Fixo Ativo" : "Dinâmico Ativo")
      : "Inativo";

   // Body labels
   ObjectSetString(0, "LBL_NOME_ESTRATEGIA", OBJPROP_TEXT, InpNomeEstrategia != "" ? InpNomeEstrategia : "---");
   ObjectSetString(0, "LBL_PLANO",     OBJPROP_TEXT, "Plano: "   + g_licensePlan);
   ObjectSetString(0, "LBL_STATUS",    OBJPROP_TEXT, "Status: "  + g_licenseStatus);
   ObjectSetString(0, "LBL_EXPIRA",    OBJPROP_TEXT, "Expira: "  + g_licenseExpiration);
   ObjectSetString(0, "LBL_ATIVO",     OBJPROP_TEXT, "Ativo: "   + _Symbol);
   ObjectSetString(0, "LBL_GRID",      OBJPROP_TEXT, "Grid: "    + gridStatus);
   ObjectSetString(0, "LBL_STATUS_OP", OBJPROP_TEXT, "Op: "      + statusOp);
   ObjectSetString(0, "LBL_HORA",      OBJPROP_TEXT, "Hora: "    + TimeToString(TimeCurrent(), TIME_SECONDS));
   ObjectSetInteger(0, "LBL_STATUS",   OBJPROP_COLOR, g_licenseColor);

   // Cards
   ObjectSetString(0, "CARD_ABERTO_VAL", OBJPROP_TEXT, DoubleToString(aberto, 2));
   ObjectSetString(0, "CARD_DIA_VAL",    OBJPROP_TEXT, DoubleToString(dailyProfit, 2));
   ObjectSetString(0, "CARD_SEMANA_VAL", OBJPROP_TEXT, DoubleToString(weeklyProfit, 2));
   ObjectSetString(0, "CARD_MES_VAL",    OBJPROP_TEXT, DoubleToString(monthlyProfit, 2));

   ObjectSetInteger(0, "CARD_ABERTO_BG", OBJPROP_BGCOLOR, aberto        >= 0 ? C'0,110,60' : C'120,0,0');
   ObjectSetInteger(0, "CARD_DIA_BG",    OBJPROP_BGCOLOR, dailyProfit   >= 0 ? C'0,110,60' : C'120,0,0');
   ObjectSetInteger(0, "CARD_SEMANA_BG", OBJPROP_BGCOLOR, weeklyProfit  >= 0 ? C'0,110,60' : C'120,0,0');
   ObjectSetInteger(0, "CARD_MES_BG",    OBJPROP_BGCOLOR, monthlyProfit >= 0 ? C'0,110,60' : C'120,0,0');

   ChartRedraw();
}

void RemoverPainel()
{
   string objetos[] = {
      PANEL_NAME, PANEL_HEADER_NAME, PANEL_BODY_NAME,
      "SLYBOT_LOGO", "LBL_TITLE", "LBL_RESULTADO_DIA",
      BTN_COLLAPSE, "BTN_POWER_BG", "BTN_POWER_TXT",
      "LBL_NOME_ESTRATEGIA", "LBL_PLANO", "LBL_STATUS", "LBL_EXPIRA",
      "LBL_ATIVO", "LBL_GRID", "LBL_STATUS_OP", "LBL_HORA",
      "CARD_ABERTO_BG", "CARD_ABERTO_TIT", "CARD_ABERTO_VAL",
      "CARD_DIA_BG",    "CARD_DIA_TIT",    "CARD_DIA_VAL",
      "CARD_SEMANA_BG", "CARD_SEMANA_TIT", "CARD_SEMANA_VAL",
      "CARD_MES_BG",    "CARD_MES_TIT",    "CARD_MES_VAL",
      "BTN_CLOSE_ALL_BG", "BTN_CLOSE_ALL_TXT"
   };
   for(int i = 0; i < ArraySize(objetos); i++)
      if(ObjectFind(0, objetos[i]) >= 0) ObjectDelete(0, objetos[i]);
}

//+------------------------------------------------------------------+
//| Função para processar cliques em objetos                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   // COLLAPSE
   if(sparam == BTN_COLLAPSE)
   {
      g_panelCollapsed = !g_panelCollapsed;
      ObjectSetString(0, BTN_COLLAPSE, OBJPROP_TEXT, g_panelCollapsed ? ">" : "▼");
      ObjectSetInteger(0, PANEL_NAME, OBJPROP_YSIZE, GetPanelHeight());

      string objetosBody[] = {
         PANEL_BODY_NAME,
         "LBL_NOME_ESTRATEGIA", "LBL_PLANO", "LBL_STATUS", "LBL_EXPIRA",
         "LBL_ATIVO", "LBL_GRID", "LBL_STATUS_OP", "LBL_HORA",
         "CARD_ABERTO_BG", "CARD_ABERTO_TIT", "CARD_ABERTO_VAL",
         "CARD_DIA_BG",    "CARD_DIA_TIT",    "CARD_DIA_VAL",
         "CARD_SEMANA_BG", "CARD_SEMANA_TIT", "CARD_SEMANA_VAL",
         "CARD_MES_BG",    "CARD_MES_TIT",    "CARD_MES_VAL",
         "BTN_CLOSE_ALL_BG", "BTN_CLOSE_ALL_TXT"
      };
      for(int i = 0; i < ArraySize(objetosBody); i++)
         if(ObjectFind(0, objetosBody[i]) >= 0)
            ObjectSetInteger(0, objetosBody[i], OBJPROP_TIMEFRAMES,
                             g_panelCollapsed ? 0 : OBJ_ALL_PERIODS);
      ChartRedraw();
      return;
   }

   // POWER
   if(sparam == "BTN_POWER_BG" || sparam == "BTN_POWER_TXT")
   {
      g_botLigado = !g_botLigado;
      color bgColor = g_botLigado ? clrLime : clrRed;
      ObjectSetInteger(0, "BTN_POWER_BG",  OBJPROP_BGCOLOR, bgColor);
      ObjectSetInteger(0, "BTN_POWER_BG",  OBJPROP_BORDER_COLOR, bgColor);
      ObjectSetString(0,  "BTN_POWER_TXT", OBJPROP_TEXT, g_botLigado ? "ON" : "OFF");
      ChartRedraw();
      return;
   }

   // PARAR E FECHAR
   if(sparam == "BTN_CLOSE_ALL_BG" || sparam == "BTN_CLOSE_ALL_TXT")
   {
      Print("Botão PARAR E FECHAR acionado — encerrando operações e bloqueando o dia.");
      CloseAllPositions();
      dailyLimitReached = true;
      ChartRedraw();
      return;
   }
}


//+------------------------------------------------------------------+
//| Atualizar dados de mercado                                        |
//+------------------------------------------------------------------+
void AtualizarDadosDoMercado() {
   g_fechaAnterior  = iClose(_Symbol, PERIOD_D1, 1);
   g_aberturaDia    = iOpen(_Symbol, PERIOD_D1, 0);
   g_precoAtual     = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   MqlRates BarData[1];
   if(CopyRates(_Symbol, mm_tempo_grafico, 0, 1, BarData) > 0)
      g_fechamentoBarra = BarData[0].close;
   else
      g_fechamentoBarra = g_precoAtual; // Fallback para preço atual
}

//+------------------------------------------------------------------+
//| Calcular preços de entrada baseados no percentual                 |
//+------------------------------------------------------------------+
void CalcularPrecosDeEntrada() {
   if(g_aberturaDia <= 0) {
      Print("AVISO: Abertura do dia inválida. Aguardando dados...");
      return;
   }
   g_precoEntradaC = g_aberturaDia * (1.0 + perc_alta  / 100.0);
   g_precoEntradaV = g_aberturaDia * (1.0 - perc_queda / 100.0);
   PrintFormat("Preços calculados: Abertura=%.2f | EntradaC=%.2f (+%.1f%%) | EntradaV=%.2f (-%.1f%%)",
               g_aberturaDia, g_precoEntradaC, perc_alta, g_precoEntradaV, perc_queda);
}

//+------------------------------------------------------------------+
//| Gerenciar horários                                                |
//+------------------------------------------------------------------+
void GerenciarHorarios() {
   datetime timeNow = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(timeNow, tm);
   g_currentTime = tm.hour * 100 + tm.min; // Ex: 09:30 -> 930
}

//+------------------------------------------------------------------+
//| Verificar se é um novo candle                                     |
//+------------------------------------------------------------------+
bool NovoCandle() {
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(_Symbol, mm_tempo_grafico, 0);
   if(last_bar_time != current_bar_time) {
      last_bar_time = current_bar_time;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Desenhar linhas de entrada no gráfico                             |
//+------------------------------------------------------------------+
void DesenharLinhas() {
   ObjectDelete(0, "LinhaPercentualAlta");
   ObjectDelete(0, "LinhaPercentualQueda");

   ObjectCreate(0, "LinhaPercentualQueda", OBJ_HLINE, 0, 0, g_precoEntradaV);
   ObjectSetInteger(0, "LinhaPercentualQueda", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "LinhaPercentualQueda", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "LinhaPercentualQueda", OBJPROP_WIDTH, 1);
   ObjectSetString(0, "LinhaPercentualQueda", OBJPROP_TEXT, "Venda: " + DoubleToString(g_precoEntradaV, _Digits));

   ObjectCreate(0, "LinhaPercentualAlta", OBJ_HLINE, 0, 0, g_precoEntradaC);
   ObjectSetInteger(0, "LinhaPercentualAlta", OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, "LinhaPercentualAlta", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "LinhaPercentualAlta", OBJPROP_WIDTH, 1);
   ObjectSetString(0, "LinhaPercentualAlta", OBJPROP_TEXT, "Compra: " + DoubleToString(g_precoEntradaC, _Digits));

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Validação de Licença                                             |
//+------------------------------------------------------------------+
bool ValidateLicense()
{
   if(MQLInfoInteger(MQL_TESTER))
   {
      g_licenseStatus = "TEST MODE";
      g_licenseColor  = clrAqua;
      return true;
   }

   if(StringLen(LICENSE_KEY) < 10)
   {
      g_licensePlan       = "---";
      g_licenseExpiration = "---";
      g_licenseStatus     = "Insira sua licença";
      g_licenseColor      = clrOrange;
      return false;
   }

   string json =
      "{"
      "\"mt5_login\":\""  + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\","
      "\"server\":\""     + AccountInfoString(ACCOUNT_SERVER)  + "\","
      "\"license_key\":\"" + LICENSE_KEY + "\","
      "\"broker\":\""     + AccountInfoString(ACCOUNT_COMPANY) + "\","
      "\"secret\":\""     + API_SECRET + "\""
      "}";

   char post[];
   int size = StringToCharArray(json, post, 0, StringLen(json));
   ArrayResize(post, size);

   string headers = "Content-Type: application/json\r\n";
   char result[];
   int res = WebRequest("POST", API_URL, headers, 5000, post, result, headers);

   if(res == -1)
   {
      g_licensePlan       = "---";
      g_licenseExpiration = "---";
      g_licenseStatus     = "Servidor offline";
      g_licenseColor      = clrRed;
      return false;
   }

   string response = CharArrayToString(result);
   CJAVal data;
   if(!data.Deserialize(response)) { Print("Erro ao interpretar JSON."); return false; }

   bool valid = data["valid"].ToBool();
   if(!valid)
   {
      string reason = data["reason"].ToStr();
      if(reason == "invalid_license")    reason = "Licença inválida";
      else if(reason == "expired")       reason = "Licença expirada";
      else if(reason == "account_not_allowed") reason = "Conta não autorizada";
      else if(reason == "server_not_allowed")  reason = "Servidor não autorizado";
      else if(reason == "license_blocked")     reason = "Licença bloqueada";
      else if(reason == "not_found")           reason = "Licença não encontrada";
      g_licensePlan       = "---";
      g_licenseExpiration = "---";
      g_licenseStatus     = reason;
      g_licenseColor      = clrRed;
      return false;
   }

   g_licensePlan       = data["plan"].ToStr();
   g_licenseExpiration = data["expiration"].ToStr();
   g_licenseStatus     = "✔ Ativa";
   g_licenseColor      = clrLime;
   return true;
}

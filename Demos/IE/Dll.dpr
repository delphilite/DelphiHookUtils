library Dll;

uses
  Windows, WinInet, HookUtils;

var
  HttpOpenRequestWNext: function(hConnect: HINTERNET; lpszVerb: LPWSTR;
    lpszObjectName: LPWSTR; lpszVersion: LPWSTR; lpszReferrer: LPWSTR;
    lplpszAcceptTypes: PLPSTR; dwFlags: DWord;
    dwContext: DWORD_PTR): HINTERNET; stdcall;

function HttpOpenRequestWCallBack(hConnect: HINTERNET; lpszVerb: LPWSTR;
  lpszObjectName: LPWSTR; lpszVersion: LPWSTR; lpszReferrer: LPWSTR;
  lplpszAcceptTypes: PLPSTR; dwFlags: DWord;
  dwContext: DWORD_PTR): HINTERNET; stdcall;
var
  S: string;
begin
  // 先直接调用原始函数
  Result := HttpOpenRequestWNext(hConnect, lpszVerb, lpszObjectName, lpszVersion,
    lpszReferrer, lplpszAcceptTypes, dwFlags, dwContext);

  if Result = nil then
  begin
    // 打印错误...
    Exit;
  end;
  // 添加自定义的http标头
  S := 'X-MyHttpHeader: HeaderValue';
  if not Wininet.HttpAddRequestHeaders(Result, PChar(S), Length(S),
    Wininet.HTTP_ADDREQ_FLAG_ADD or Wininet.HTTP_ADDREQ_FLAG_REPLACE) then
  begin
    // 打印错误...
    Exit;
  end;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2016.10.09
//功能：初始化、挂接 API
//参数：
//注意：如果 HookProc 的 DLL 没有被 LoadLibrary 下 Hook 会失败，建议先手工 Load
////////////////////////////////////////////////////////////////////////////////
procedure DllEntryPoint(dwReason: DWord);
begin
  case dwReason of
    DLL_PROCESS_ATTACH:
      begin
        if HookUtils.HookProc('WinInet.dll', 'HttpOpenRequestW', @HttpOpenRequestWCallBack, @HttpOpenRequestWNext) then
        begin
          // Hook 成功...
        end
        else
        begin
          // Hook 失败...
        end;
      end;
    DLL_PROCESS_DETACH:
      begin
        if HookUtils.UnHookProc(@HttpOpenRequestWNext) then
        begin
          // UnHook 成功...
        end
        else
        begin
          // UnHook 失败...
        end;
      end;
    DLL_THREAD_ATTACH:
      begin
      end;
    DLL_THREAD_DETACH:
      begin
      end;
  end;
end;

begin
  DllProc := @DllEntryPoint;
  DllEntryPoint(DLL_PROCESS_ATTACH);
end.
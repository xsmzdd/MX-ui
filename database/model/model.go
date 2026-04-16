package model

import (
	"fmt"
	"x-ui/util/json_util"
	"x-ui/xray"
)

type Protocol string

const (
	VMess       Protocol = "vmess"
	VLESS       Protocol = "vless"
	Dokodemo    Protocol = "Dokodemo-door"
	Http        Protocol = "http"
	Trojan      Protocol = "trojan"
	Shadowsocks Protocol = "shadowsocks"
)

type User struct {
	Id       int    `json:"id" gorm:"primaryKey;autoIncrement"`
	Username string `json:"username"`
	Password string `json:"password"`
}

type Inbound struct {
	Id         int   `json:"id" form:"id" gorm:"primaryKey;autoIncrement"`
	UserId     int   `json:"-"`
	Up         int64 `json:"up" form:"up"`
	Down       int64 `json:"down" form:"down"`
	Total      int64 `json:"total" form:"total"`
	Remark     string `json:"remark" form:"remark"`
	Enable     bool   `json:"enable" form:"enable"`
	ExpiryTime int64  `json:"expiryTime" form:"expiryTime"`

	// auto reset
	Reset         bool  `json:"reset" form:"reset"`
	ResetDay      int   `json:"resetDay" form:"resetDay"`
	LastResetTime int64 `json:"lastResetTime" form:"lastResetTime"`

	// config part
	Listen         string   `json:"listen" form:"listen"`
	Port           int      `json:"port" form:"port" gorm:"unique"`
	Protocol       Protocol `json:"protocol" form:"protocol"`
	Settings       string   `json:"settings" form:"settings"`
	StreamSettings string   `json:"streamSettings" form:"streamSettings"`
	Tag            string   `json:"tag" form:"tag" gorm:"unique"`
	Sniffing       string   `json:"sniffing" form:"sniffing"`
}

func (i *Inbound) GenXrayInboundConfig() *xray.InboundConfig {
	listen := i.Listen
	if listen != "" {
		listen = fmt.Sprintf("\"%v\"", listen)
	}
	return &xray.InboundConfig{
		Listen:         json_util.RawMessage(listen),
		Port:           i.Port,
		Protocol:       string(i.Protocol),
		Settings:       json_util.RawMessage(i.Settings),
		StreamSettings: json_util.RawMessage(i.StreamSettings),
		Tag:            i.Tag,
		Sniffing:       json_util.RawMessage(i.Sniffing),
	}
}

type InboundOutbound struct {
	Id        int    `json:"id" gorm:"primaryKey;autoIncrement"`
	UserId    int    `json:"userId" form:"userId" gorm:"index"`
	InboundId int    `json:"inboundId" form:"inboundId" gorm:"uniqueIndex"`
	Enable    bool   `json:"enable" form:"enable"`
	Protocol  string `json:"protocol" form:"protocol"`
	Address   string `json:"address" form:"address"`
	Port      int    `json:"port" form:"port"`
	Username  string `json:"username" form:"username"`
	Password  string `json:"password" form:"password"`
}

func (*InboundOutbound) TableName() string {
	return "inbound_outbounds"
}

type Setting struct {
	Id    int    `json:"id" form:"id" gorm:"primaryKey;autoIncrement"`
	Key   string `json:"key" form:"key"`
	Value string `json:"value" form:"value"`
}

// Comparison-only ABI declarations from official Qt6.8.3 headers.
#include <cstddef>
#include <iostream>
#include <string>
#include <cstdlib>
struct QByteArrayView { std::ptrdiff_t size; const char *data; };
class QString {
public:
    void *header; char16_t *data; std::ptrdiff_t size;
    ~QString() {} // Returned strings kept until short-lived probe exits.
    static QString fromUtf8(QByteArrayView);
};
class QVariant {
    alignas(8) unsigned char data[32];
public:
    QVariant(bool) noexcept;
    QVariant(double) noexcept;
    QVariant(const QString&) noexcept;
    ~QVariant();
    bool toBool() const;
    QString toString() const;
};
class QJsonArray {
    void *container;
public: QJsonArray(); ~QJsonArray();
};
class QJsonObject {
    void *container;
public: QJsonObject(); ~QJsonObject();
};
class QJsonValue {
    alignas(8) unsigned char data[24];
public:
    enum Type { Null = 0 };
    QJsonValue(Type);
    QJsonValue(bool);
    QJsonValue(double);
    QJsonValue(const QString&);
    QJsonValue(const QJsonArray&);
    QJsonValue(const QJsonObject&);
    ~QJsonValue();
    QVariant toVariant() const;
};
extern "C" const char *qVersion();
void print(const QVariant& value) {
    auto text=value.toString();
    std::cout << (value.toBool()?"true":"false") << '\t';
    for (std::ptrdiff_t i=0;i<text.size;i++) std::cout << char(text.data[i]);
    std::cout << '\n';
}
int main() {
    std::cerr << "Qt " << qVersion() << '\n';
    std::string line;
    while(std::getline(std::cin,line)) {
        auto split=line.find('\t'); if(split==std::string::npos) return 2;
        auto type=line.substr(0,split),input=line.substr(split+1);
        std::cout << line << '\t';
        if(type=="string") { auto s=QString::fromUtf8({static_cast<std::ptrdiff_t>(input.size()),input.data()}); QJsonValue j(s); auto v=j.toVariant(); print(v); }
        else if(type=="number") { QJsonValue j(std::strtod(input.c_str(),nullptr)); auto v=j.toVariant(); print(v); }
        else if(type=="bool") { QJsonValue j(input=="true"); auto v=j.toVariant(); print(v); }
        else if(type=="null") { QJsonValue j(QJsonValue::Null); auto v=j.toVariant(); print(v); }
        else if(type=="array") { QJsonArray a; QJsonValue j(a); auto v=j.toVariant(); print(v); }
        else if(type=="object") { QJsonObject o; QJsonValue j(o); auto v=j.toVariant(); print(v); }
        else return 3;
    }
}

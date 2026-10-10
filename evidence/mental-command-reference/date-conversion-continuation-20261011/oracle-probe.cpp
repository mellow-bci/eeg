// Read-only installed Qt comparison probe. Minimal ABI declarations are based
// on official Qt6.8.3 headers and arm64 disassembly; never a deliverable dependency.
#include <cstddef>
#include <iostream>
#include <string>
namespace Qt { enum DateFormat { ISODateWithMs = 9 }; }
struct QStringView { std::ptrdiff_t size; const char16_t *data; };
class QString {
public:
    void *header; char16_t *data; std::ptrdiff_t size;
    // Short-lived probe intentionally does not free Qt returned string allocation.
    ~QString() {}
};
class QTimeZone {
    void *data;
public: QTimeZone(int); ~QTimeZone();
};
class QDateTime {
    void *data;
public:
    enum class TransitionResolution { RelativeToBefore = 1 };
    ~QDateTime();
    static QDateTime fromString(QStringView, Qt::DateFormat);
    bool isValid() const;
    int offsetFromUtc() const;
    void setTimeZone(const QTimeZone&,TransitionResolution);
    QString toString(Qt::DateFormat) const;
};
extern "C" const char *qVersion();
int main() {
    std::cerr << "Qt " << qVersion() << "\n";
    std::string input;
    while (std::getline(std::cin,input)) {
        std::u16string wide(input.begin(),input.end());
        auto value=QDateTime::fromString({static_cast<std::ptrdiff_t>(wide.size()),wide.data()},Qt::ISODateWithMs);
        if (!value.isValid()) { std::cout << input << "\tINVALID\n"; continue; }
        auto offset=value.offsetFromUtc(); QTimeZone zone(offset);
        value.setTimeZone(zone,QDateTime::TransitionResolution::RelativeToBefore);
        auto text=value.toString(Qt::ISODateWithMs);
        std::string output; for (std::ptrdiff_t i=0;i<text.size;i++) output+=char(text.data[i]);
        std::cout << input << '\t' << output << '\t' << offset << '\n';
    }
}

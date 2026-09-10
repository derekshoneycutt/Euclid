module EuclidElementsOverview

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("4a3a9e1f-6448-554a-8e37-52f579b7476b")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_content, initialize, clean, loop, animation_entry

"""Emit the welcome view content for Euclid's Elements."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Welcome to Euclid's Elements!}

==> <-- -> <--> <| |> <= >=

$$\frac{2\pi}{3}\;\;\; \sum \left\{\begin{matrix} 1 & 2 & 3 & 4 \\ 5 & 6 & 7 & 8 \end{matrix}\right\}\;\;\; C_n = \{e,\rho,\rho^2,\dots,\rho^{n-1}\}\;\;\; \sqrt[3]{\left(\int_0^1\begin{bmatrix} 1 & 2 & 3 & 4 \\ 5 & 6 & 7 & 8 \end{bmatrix}\right)}$$

$$x^2\;\;\; x_i\;\;\; x_i^2\;\;\; V_A\;\;\; x^{y_2}\;\;\; \left(\frac{a}{b}\right)^2$$

$$\frac{a+b}{c}\;\;\; \frac{x^2}{y_1}\;\;\; \frac{1}{1+\frac{1}{x}}\;\;\; \frac{\sqrt{x}}{\overline{y}}$$

$$\sum_{i=1}^{n} i\;\;\; \prod_{k=1}^{m} a_k\;\;\; \int_0^1 f(x)\,dx\;\;\; \lim_{x\to 0} f(x)"$$

$$\sqrt{x}\;\;\; \sqrt[n]{x+1}\;\;\; \sqrt{\frac{a}{b}}\;\;\; \left(\frac{a}{b}\right)\;\;\; \left\{\begin{array}{cc}a&b\\c&d\end{array}\right.$$

$$x^2\;\;\; x_i\;\;\; x_i^2\;\;\; V_A\;\;\; \sqrt{x}\;\;\; \sum_{i=1}^{n} i\;\;\; \prod_{k=1}^{m} a_k\;\;\; \int_0^1 f(x)\,dx\;\;\; \lim_{x\to 0} f(x)\;\;\; \frac{\sqrt{x}}{\overline{y}}$$

$$\begin{array}{@{}||l|r||@{}}\hline x&\frac{1}{2}\\[1em]\hline y&\sqrt{z}\\[-1pt]\hline\hline\end{array}$$

$$\begin{cases}x^2&x>0\\-x&x\le0\end{cases}\;\begin{dcases}\frac{1}{2}&x>0\\0&x\le0\end{dcases}\;\begin{aligned}a&=\begin{smallmatrix}1&2\\3&4\end{smallmatrix}\\b&=\sqrt{z}\end{aligned}$$

$${\textstyle \frac{a}{b}}+\frac{c}{d}\;\dfrac{1}{2}+\tfrac{3}{4}\;\sum\nolimits_{i=1}^n i+\int\limits_0^1 x\;\binom{n}{k}+\dbinom{p}{q}+\tbinom{r}{s}"$$

$$\bigl(x\bigr)+\Bigl[x\Bigr]+\biggl\{x\biggr\}\;\left\{x\middle|y\middle\|z\right\}\;\check a+\breve b+\acute c+\grave d+\mathring e\;\overset{!}{=}+\underset{n}{x}\;\overbrace{a+b+c}^{n}+\underbrace{x+y}_{m}$$

\noindent {\bfseries Bold {\itshape italic}} \textnormal{normal} \% \# \_ \& \{ \}~kept\ space% hidden
\par\begin{center}Centered JuliaMono prose.\end{center}\begin{flushright}Right aligned prose.\end{flushright}

\begin{quote}A short quotation uses symmetric margins without paragraph indentation.\end{quote}

\begin{quotation}A longer quotation also uses symmetric margins. Its first paragraph is not indented.

Its following paragraph returns to ordinary first-line indentation.\end{quotation}

\begin{itemize}
\item A bullet item with enough text to demonstrate hanging indentation when the panel becomes narrow.
\item A nested ordered construction:
\begin{enumerate}
\item Choose two points $A$ and $B$.
\item Draw the segment $AB$ and compare it with
\[\overline{AB} = \sqrt{(x_B-x_A)^2+(y_B-y_A)^2}.\]
\end{enumerate}
\end{itemize}

\begin{description}
\item[Point] That which has no part.
\item[\textcolor{steelblue}{Extended construction term}] A wide styled term moves above its body when the shared label column reaches its bound.
\end{description}"""
end

"""Initialize the null animation and publish the Elements overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Advance the shared null animation for the Elements overview."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the Elements overview."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the Elements overview."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        clean(state_ptr)
    else
        return false
    end
    return true
end

end

AnimationCatalog.animation(
    EuclidElementsOverview.AnimationId, EuclidElementsOverview.animation_entry)
